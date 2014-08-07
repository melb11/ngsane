#!/bin/bash -e

# author: Hugh French and Fabian Buske
# date: March 2014
echo ">>>>> Count tables from htseqcount output"
echo ">>>>> startdate "`date`
echo ">>>>> hostname "`hostname`
echo ">>>>> job_name "$JOB_NAME
echo ">>>>> job_id "$JOB_ID
echo ">>>>> $(basename $0) $*"

function usage {
echo -e "usage: $(basename $0) -k NGSANE -f INPUTFILE -o OUTDIR [OPTIONS]"
exit
}

if [ ! $# -gt 3 ]; then usage ; fi

#INPUTS                                                                                                           
while [ "$1" != "" ]; do
    case $1 in
        -k | --toolkit )        shift; CONFIG=$1 ;;     # location of the NGSANE repository                       
        -f | --file )           shift; FILES=$1 ;;  # input file                                                       
        -o | --outdir )         shift; OUTDIR=$1 ;;     # output dir                                                     
        --recover-from )        shift; RECOVERFROM=$1 ;; # attempt to recover from log file
        -h | --help )           usage ;;
        * )                     echo "don't understand "$1
    esac
    shift
done

#PROGRAMS
. $CONFIG
. ${NGSANE_BASE}/conf/header.sh
. $CONFIG

################################################################################
CHECKPOINT="programs"

# save way to load modules that itself loads other modules
hash module 2>/dev/null && for MODULE in $MODULE_HTSEQCOUNT; do module load $MODULE; done && module list 

export PATH=$PATH_HTSEQCOUNT:$PATH
echo "PATH=$PATH"

echo -e "--NGSANE      --\n" $(trigger.sh -v 2>&1)
## [TODO] test and output versions of software utilized in this mod 

echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="parameters"
echo "[NOTE] Files: $FILES"
OLDFS=$IFS
IFS=","
DATASETS=""
for f in $FILES; do
    # get basename of f

    n=${f/%$ASD.bam/}
    FILE=${n/$TASK_TOPHAT/$TASK_HTSEQCOUNT}
    # get directory
    d=$(dirname $f)
    d=${d##*/}    # add to dataset
    if [ -n "$FILE" ]; then 
        DATASETS="${DATASETS[@]} ${FILE[@]}"
    fi
done
IFS=" "

echo "[NOTE] datasets"
echo "[NOTE] echo $DATASETS"

annoF=${GTF##*/}
anno_version=${annoF%.*}

echo "[NOTE] GTF"
echo "[NOTE] echo $anno_version"

echo "[NOTE] ${OUTDIR}"

# delete old files unless attempting to recover
#remove old files
if [ -z "$RECOVERFROM" ]; then
    if [ -d $OUTDIR ]; then rm -r $OUTDIR; fi
fi

mkdir -p $OUTDIR 

# unique temp folder that should be used to store temporary files
THISTMP=$TMP"/"$(whoami)"/"$(echo $OUTDIR | md5sum | cut -d' ' -f1)
mkdir -p $THISTMP

echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="recall files from tape"

if [ -n "$DMGET" ]; then
    dmget -a $INPUTFILE
    dmget -a $OUTDIR/*
    # TODO add additional resources that are required and may need recovery from tape
fi
    
echo -e "\n********* $CHECKPOINT\n"   
################################################################################
CHECKPOINT="Make tables of counts."
if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 

    echo "[NOTE] Make tables of counts."
         
    for GTF in  "$anno_version" ; do
        for MODE in "union" "intersection-strict" "intersection-nonempty"; do
            for ATTR in "gene_id" "transcript_id"; do 
       
                [ -f ${THISTMP}/files.txt ] &&  rm ${THISTMP}/files.txt
                touch ${THISTMP}/files.txt
                
                array=(${DATASETS[@]})
                array=( "${array[@]/%//${GTF}.${MODE}.${ATTR}}" )                  
                
                for THIS_FILE in "${array[@]}"; do
                    [ -f $THIS_FILE ] && echo $THIS_FILE "Found" >> ${THISTMP}/files.txt || echo "Not found" >> ${THISTMP}/files.txt           

       
                done
       
                if grep -q "Not found" ${THISTMP}/files.txt;then    
                    echo "[NOTE] ${GTF}.${MODE}.${ATTR} - not found, skipping."            
                else
                    echo "[NOTE] ${GTF}.${MODE}.${ATTR} - found, making count table."  
                    [ -f ${THISTMP}/joinedfile.txt ] && rm ${THISTMP}/joinedfile.txt
                    
                    for i in "${array[@]}"; do
                        if [ ! -f ${THISTMP}/joinedfile.txt ]; then
                            cat ${i} > ${THISTMP}/joinedfile.txt 
                        else
                            cut -f 2 ${i} | paste ${THISTMP}/joinedfile.txt -  > ${THISTMP}/tmp.txt                            
                            mv ${THISTMP}/tmp.txt ${THISTMP}/joinedfile.txt
                        fi
                    done

                    echo "${array[@]##*${TASK_HTSEQCOUNT}}" |  sed 's/ /,/g' | sed "s/\/${GTF}.${MODE}.${ATTR}//g" | sed 's/\///g'   > ${THISTMP}/tmp.txt
                    awk '{print "gene," $0;}' ${THISTMP}/tmp.txt > ${THISTMP}/out.csv
                    cat ${THISTMP}/joinedfile.txt | sed 's/\t/,/g' >> ${THISTMP}/out.csv
                    mv ${THISTMP}/out.csv ${OUTDIR}/${anno_version}.${MODE}.${ATTR}.csv
                    echo "[NOTE] OUTFILE ${OUTDIR}/${anno_version}.${MODE}.${ATTR}.csv "
                fi
            done
        done
    done
        
    # mark checkpoint
    echo -e "\n********* $CHECKPOINT\n"
    
fi
################################################################################
CHECKPOINT="cleanup counts."  
  
  [ -f ${THISTMP}/out.csv ] && rm ${THISTMP}/out.csv
  [ -f ${THISTMP}/joinedfile.txt ] && rm ${THISTMP}/joinedfile.txt
  [ -f ${THISTMP}/files.txt ] && rm ${THISTMP}/files.txt

echo -e "\n********* $CHECKPOINT\n"

################################################################################




echo ">>>>> Count tables from htseqcount output - FINISHED"
echo ">>>>> enddate "`date`