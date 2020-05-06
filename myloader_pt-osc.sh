# -d myloader directory
# -D pt-osc database
# -T tablename
# -t amoount of threads for myloader

function myecho {
  echo "$(date ): $*"
}

working_path=$PWD
pk_column=id
min_id=1
chunk_size=1000
threads=4
credentials=""
ignore_download="no"
while [[ $# -gt 0 ]]
do
key="$1"
case $key in
    -D|--database)
    database="$2"
    shift
    shift
    ;;
    -d|--directory)
    working_path="$2"
    shift
    shift
    ;;
    -T|--table-name)
    table_name="$2"
    shift
    shift
    ;;
    -t|--threads)
    threads="$2"
    shift
    shift
    ;;
    -u|--user)
    user="$2"
    shift
    shift
    ;;
    -p|--password)
    password="$2"
    shift
    shift
    ;;
    --mix-id)
    min_id="$2"
    shift
    shift
    ;;
    --pk-column)
    pk_column="$2"
    shift
    shift
    ;;
    --max-id)
    max_id="$2"
    shift
    shift
    ;;
    --chunk-size)
    chunk_size="$2"
    shift
    shift
    ;;
    --ignore-download)
    ignore_download="yes"
    shift
    ;;
    --alter)
    alter_statement="$2"
    shift
    shift
    ;;
    *)
    shift
    ;;
esac
done

if [ "$database" == "" ]
then
  echo "Database option not found. Use -D <database>"
  exit 1
fi

if [ "$table_name" == "" ]
then
  echo "Table option not found. Use -T <table>"
  exit 1
fi

if [ "$alter_statement" == "" ]
then
  echo "Alter option not found. Use --alter ' statement '"
  exit 1
fi

if [ "$user" != "" ]
then
  credentials="$credentials -u $user" 
fi

if [ "$password" != "" ]
then
  credentials="$credentials -p'$password'"
fi

ptosc_log=".ptosc.log"
touch /tmp/pause.file

pt-online-schema-change $credentials --dry-run --alter="$alter_statement" --print D=${database},t=${table_name} > ${ptosc_log}
insert_statement=$(grep INSERT ${ptosc_log})

if [ "$insert_statement" == "" ]
then
  echo "Empty insert statement"
  exit 1
fi

bin_path="${working_path}/.bin"
git_url="https://raw.githubusercontent.com/david-ducos-percona/myloader_pt-osc/master/"

mkdir -p ${bin_path}

ptosc=${bin_path}/pt-online-schema-change

if [ "$ignore_download" != "yes" ]
then
   wget percona.com/get/pt-online-schema-change > /dev/null 2>&1
   chmod u+x pt-online-schema-change
   rm ${bin_path}/pt-online-schema-change
   mv pt-online-schema-change $bin_path

   version=$( ${ptosc} --version | cut -d' ' -f2 )
   ptosc_patch_filename=pt-online-schema-change.${version}.patch
   rm $ptosc_patch_filename

   wget ${git_url}/${ptosc_patch_filename} > /dev/null 2>&1

   patch ${ptosc} ${ptosc_patch_filename}
fi

ptosc_log="${bin_path}/ptosc.log"
ptosc_pause="${bin_path}/pause_file"
touch $ptosc_pause
myecho "Starting pt-osc "
$ptosc --pause-file=$ptosc_pause --alter="$alter_statement" --no-data --execute D=${database},t=${table_name} > ${ptosc_log} & 
process_id=$!
sleep 0.2
schema_file="${database}.${table_name}-schema.sql"

# It can be empty:
> ${working_path}/metadata
> ${working_path}/${schema_file}

if [ "${max_id}" == "" ];
then
  max_id=$( echo "select max(${pk_column}) from ${table_name}" | mysql $credentials $database -NA )
fi

myecho "Creating the INSERT INTO files"
last=$(( ($max_id - $min_id ) / $chunk_size + 1 ))

from=${min_id}
pids=""
for m in $(seq -w 00000 00003 )
do
	from=$(( ${min_id} + $m * $chunk_size ))
	for i in $(seq -w $m 4 $last ) # | sort -R)
	do
	  to=$(( $from + $chunk_size - 1 ))
	  filename="${working_path}/${database}.${table_name}.${i}.sql"
	  echo "${insert_statement}" | sed "s/FROM .*/FROM \`${database}\`.\`${table_name}\` WHERE ${pk_column} between $from AND $to ;/g " > $filename
	  from=$(( $to + 1 + 3 * $chunk_size ))
	done &
pids+=" $!"
done

for p in $pids; do
  wait $p
done
myecho "All pids finished"

# check if table is created
echo "SHOW CREATE TABLE \`$(echo $insert_statement | cut -f 2-4 -d'`')\`" | mysql > /dev/null
error=$?
if (( $error > 0 ))
then
	myecho "New table not found"
	exit $error
fi

myecho "Starting myloader"
# We are reading to import the data
#/root/git/mydumper/myloader -q 1 -d ${working_path} -t $threads $credentials 
myloader -q 1 -d ${working_path} -t $threads $credentials

myecho "Removing pause file"
rm $ptosc_pause
myecho "Waiting to pt-osc to rename tables..."
wait $process_id
