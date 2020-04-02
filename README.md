# myloader_pt-osc
pt-online-schema-change emulates the way that MySQL alters tables internally, but it works on a copy of the table you wish
to alter. It executes INSERT statements to import the data, that runs in a single connection to fill the new table.
myloader_pt-osc.sh uses myloader to execute parallel insert, instead of using pt-online-schema-change internal inserts.

# Patch file
There are 2 changes that we needed to perform on pt-online-schema-change:
1- Be able to stop the execution after the copy of the table is created
2- Tell pt-online-schema-change that no data needs to be imported

We are adding the --no-data to tell pt-online-schema change to do not import the data to the new table. 
pt-online-schema-change is able to stop the execution with --pause-file option. The patch file includes the code to stop 
the execution when --no-data and --pause-file is used.

# Procedure
The script is performing several tasks:
- Starting the pt-online-schema-change which is going to stop after creating the new table and triggers.
- Creating a backup directory in a format that myloader is able to take.
- Start the myloader execution.
- Resume pt-online-schema-change after myloader finishes and swap the tables.

Take into consideration that this script is not design to support multi column nor non integer primary keys

# Conclusion and expectation
I would like to see this implemented inside pt-online-schema-change but until this happend, this might be an alternative.

