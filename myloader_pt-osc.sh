database=$1

# sbtest1
from_table=$2

# sbtest1_new
# to_table=$3

chunk_size=$3
from=$4
final_id=$5

i=0
last=$(( ($final_id - $from ) / $chunk_size + 1 ))


ptosc_options="D=${database},t=${from_table}"

to_table=$(./pt-online-schema-change ${ptosc_options} --no-drop-new-table --alter="engine innodb" --no-swap-tables --dry-run | grep "DROP TABLE IF EXISTS" | cut -d'`' -f4)
schema_file="${database}.${to_table}-schema.sql"

> metadata
> ${schema_file}



for i in $(seq -w 00000 $last)
do
  to=$(( $from + $chunk_size - 1 ))
  filename=${database}.${to_table}.${i}.sql
  echo "INSERT IGNORE INTO $to_table SELECT * FROM $from_table WHERE id between $from AND $to ;" > $filename

  from=$(( $to + 1 ))
done
