#!/usr/bin/ksh
# Script name: shell_funcs.sh

export PS_EXCLUDE="$$|cat|grep|jobmanrc|more|vi |view|cybspawn"

function build_err_msg
{
  # Build error messages which may be multi-line.

  # The following variable must be defined in the calling module:
  #   ERR_MSG

  ADDL_MSG=${1}
  if [ -z "$ERR_MSG" ]; then
    ERR_MSG=${ADDL_MSG}
  else
    ERR_MSG="${ERR_MSG}\n${ADDL_MSG}"
  fi

  return 0
}

################################################################################
function validate_script
{
  # Get info from ipse_gvi.ini and use it for validations. This is test
  # Validate that the SID_NAME parameter contains a valid database on the server
  # it is being run on and validate that the Unix user can run this script.

  # The following variables must be defined in the calling module:
  #   ERR_MSG
  #   HOSTNAME

  # Initialize variables
  . ~/.paths # source in IPSE or GV version in case it is not already done
  export USER_NAME=$(whoami)
  SID_NAME=${1}
  # We will phase out INI_DIR_OLD (which used to be INI_DIR)
  # We don't need to actually receive all arguments
  # Calling script can remove 2nd arg and send 3rd arg to 2nd position
# INI_DIR_OLD=${2} # As $2 points to log dir, use src instead of log for INI_DIR
  if [ $# -eq 2 ]; then
    IPSE_OR_GVI=${2}
  else
    IPSE_OR_GVI=${3}
  fi

# INI_DIR="/opt/ipse/sw1/ips/src"
  # INI_DIR has been replaced by PRIME_SRC_DIR which comes from .paths
  TOT_LINES=$(wc -l ${PRIME_SRC_DIR}/ipse_gvi.ini | awk '{print $1}')

  # Get section boundaries
  SUM_SEC_LINENO=$(cat ${PRIME_SRC_DIR}/ipse_gvi.ini | \
        grep -n "^\[Summary_Section\]$" | awk -F":" '{print $1}')
  SRV_SEC_LINENO=$(cat ${PRIME_SRC_DIR}/ipse_gvi.ini | \
        grep -n "^\[Servers_Section\]$" | awk -F":" '{print $1}')
  DB_SEC_LINENO=$(cat ${PRIME_SRC_DIR}/ipse_gvi.ini | \
        grep -n "^\[Databases_Section\]$" | awk -F":" '{print $1}')

  # Search Summary_Section to validate that the server is valid
  CUR_LINENO=$(cat ${PRIME_SRC_DIR}/ipse_gvi.ini | \
        grep -n "^server_nm=${HOSTNAME}$" | awk -F":" '{print $1}')
  if [ -z "$CUR_LINENO" ]; then
    CUR_LINENO=0
  fi
  if [[ $CUR_LINENO -le $SUM_SEC_LINENO || $CUR_LINENO -ge $SRV_SEC_LINENO ]]; then
    build_err_msg "    This server, ${HOSTNAME}, is not valid to run this script."
    return 30
  fi

  # Search Servers_Section to get info about server
  CUR_LINENO=$(cat ${PRIME_SRC_DIR}/ipse_gvi.ini | \
        grep -n "^\[${HOSTNAME}\]$" | awk -F":" '{print $1}')
  if [ -z "$CUR_LINENO" ]; then
    CUR_LINENO=0
  fi
  if [[ $CUR_LINENO -le $SRV_SEC_LINENO || $CUR_LINENO -ge $DB_SEC_LINENO ]]; then
    build_err_msg "    The ipse_gvi.ini file is corrupt.  Server data missing for ${HOSTNAME}."
    return 30
  fi

  # Validate SID_NAME parameter and get additional variables from ipse_gvi.ini
  if [ -z "$SID_NAME" ]; then
    build_err_msg "    No Database SID specified."
    build_err_msg "      Specify with the -d option."
    return 31
  else

    SID_VALID="F"
    CONTINUE="T"
    while [ "$CONTINUE" = "T" ]; do
      CUR_LINENO=$(($CUR_LINENO+1))
      if [[ $CUR_LINENO -eq $DB_SEC_LINENO || $CUR_LINENO -eq $TOT_LINES ]]; then
        CONTINUE="F (reached Databases_Section or last line of file)"
      fi
      TXT=$(head -${CUR_LINENO} ${PRIME_SRC_DIR}/ipse_gvi.ini | tail -1)
      if [ -n "$TXT" ]; then
        LEFT_CHAR1=$(print $TXT | cut -c-1)
        if [ "$LEFT_CHAR1" = "[" ]; then
          CONTINUE="F (reached next bracket)"
        elif [ "$LEFT_CHAR1" != ";" ]; then
          PARM=$(print $TXT | awk -F"=" '{print $1}')
          VALUE=$(print $TXT | awk -F"=" '{print $2}')
          if [[ "$PARM" = "db_sid" && "$VALUE" = "$SID_NAME" ]]; then
            SID_VALID="T"
          elif [ "$PARM" = "server_desc" ]; then
            export SERVER_DESC="${VALUE}"
          elif [ "$PARM" = "production" ]; then
            export PRODUCTION="${VALUE}"
          elif [ "$PARM" = "ipse_on_server" ]; then
            export IPSE_ON_SERVER="${VALUE}"
          elif [ "$PARM" = "ipse_server" ]; then
            export IPSE_SERVER="${VALUE}"
          elif [ "$PARM" = "gv_on_server" ]; then
            export GV_ON_SERVER="${VALUE}"
          elif [ "$PARM" = "gv_server" ]; then
            export GV_SERVER="${VALUE}"
          fi
        fi
      fi
    done

    if [ "$SID_VALID" = "F" ]; then
      build_err_msg "    Database ${SID_NAME} is not a valid database on this server!"
      return 31
    fi
    if [[ -z "$SERVER_DESC" || -z "$PRODUCTION" || -z "$IPSE_ON_SERVER" || -z "$GV_ON_SERVER" ]]; then
      build_err_msg "    The ipse_gvi.ini file is corrupt.  Some server data missing for ${HOSTNAME}."
      return 30
    fi

  fi

  # Search Databases_Section to get info about database
  CUR_LINENO=$(cat ${PRIME_SRC_DIR}/ipse_gvi.ini | \
        grep -n "^\[${SID_NAME}\]$" | awk -F":" '{print $1}')
  if [ -z "$CUR_LINENO" ]; then
    CUR_LINENO=0
  fi
  if [[ $CUR_LINENO -le $DB_SEC_LINENO || $CUR_LINENO -ge $TOT_LINES ]]; then
    build_err_msg "    The ipse_gvi.ini file is corrupt.  Database data missing for ${SID_NAME}."
    return 31
  fi

  # Validate Unix user, whether IPSE or GVI,
  # and get additional variables from ipse_gvi.ini
  USER_VALID="F"
  IPSE_GVI_VALID="T"
  CONTINUE="T"
  while [ "$CONTINUE" = "T" ]; do
    CUR_LINENO=$(($CUR_LINENO+1))
    if [ $CUR_LINENO -eq $TOT_LINES ]; then
      CONTINUE="F (reached last line of file)"
    fi
    TXT=$(head -${CUR_LINENO} ${PRIME_SRC_DIR}/ipse_gvi.ini | tail -1)
    if [ -n "$TXT" ]; then
      LEFT_CHAR1=$(print $TXT | cut -c-1)
      if [ "$LEFT_CHAR1" = "[" ]; then
        CONTINUE="F (reached next bracket)"
      elif [ "$LEFT_CHAR1" != ";" ]; then
        PARM=$(print $TXT | awk -F"=" '{print $1}')
        VALUE=$(print $TXT | awk -F"=" '{print $2}')
        if [[ "$PARM" = "unix_user" && "$VALUE" = "$USER_NAME" ]]; then
          USER_VALID="T"
        elif [[ "$PARM" = "ipse_db" && "$VALUE" = "F" && "$IPSE_OR_GVI" = "I" ]]; then
          IPSE_GVI_VALID="F"
          build_err_msg "    Database ${SID_NAME} is not an IPSE database and must be!"
        elif [[ "$PARM" = "gv_db" && "$VALUE" = "F" && "$IPSE_OR_GVI" = "G" ]]; then
          IPSE_GVI_VALID="F"
          build_err_msg "    Database ${SID_NAME} is not a GVI database and must be!"
        elif [ "$PARM" = "other_sid" ]; then
          export OTHER_SID="${VALUE}"
        fi
      fi
    fi
  done

  if [ "$IPSE_GVI_VALID" = "F" ]; then
    return 32
  elif [ "$USER_VALID" = "F" ]; then
    build_err_msg "    User ${USER_NAME} is not permitted to run this script!"
    return 32
  fi

  return 0
} # validate_script

################################################################################
function ck_already_running
{
  # Check if a script is already running and fail if it is

  # The following variable must be defined in the calling module:
  #   SID_NAME

  PROC_TO_CK=${1}
  OTHER=${2}
  PROC_CNT=$(ps -ef | grep ${PROC_TO_CK} | grep "$SID_NAME" |
           egrep -v "$PS_EXCLUDE" | wc -l | awk '{print $1}')
  print "$(date +'%x %X') Counting ${OTHER}${PROC_TO_CK} running for ${SID_NAME}"
  printf '%-75s' "$(date +'%x %X')   Number of script(s) running:"
  printf ':%4.f\n' $PROC_CNT
  if [ $PROC_CNT -ne 0 ]; then
    print "$(date +'%x %X') ${PROC_TO_CK} already running for ${SID_NAME}"
    print "$(date +'%x %X')   Retry in 5 seconds"
    sleep 5
    PROC_CNT=$(ps -ef | grep ${PROC_TO_CK} | grep "$SID_NAME" |
             egrep -v "$PS_EXCLUDE" | wc -l | awk '{print $1}')
    printf '%-75s' "$(date +'%x %X')   Number of script(s) running:"
    printf ':%4.f\n' $PROC_CNT
    if [ $PROC_CNT -ne 0 ]; then
      print "$(date +'%x %X') ${PROC_TO_CK} already running for ${SID_NAME}; Exiting"
      return 2
    fi
  fi
  return 0
} # ck_already_running

################################################################################
function ck_not_running
{
  # Check if a script is not running and fail if it is not

  # The following variable must be defined in the calling module:
  #   SID_NAME

  PROC_TO_CK=${1}
  PROC_CNT=$(ps -ef | grep ${PROC_TO_CK} | grep "$SID_NAME" |
           egrep -v "$PS_EXCLUDE" | wc -l | awk '{print $1}')
  print "$(date +'%x %X') Counting ${PROC_TO_CK} running for ${SID_NAME}"
  printf '%-75s' "$(date +'%x %X')   Number of script(s) running:"
  printf ':%4.f\n' $PROC_CNT
  if [ $PROC_CNT -eq 0 ]; then
    print "$(date +'%x %X') ${PROC_TO_CK} is not running for ${SID_NAME}; Exiting"
    return 3
  fi
  return 0
} # ck_not_running

################################################################################
function before_orcl_mod
{
  # The following variables must be defined in the calling module:
  #   MAIN_LOG_DIR
  #   SQL_WRT_LG_FL
  #   SUB_PROC_NM

# print "$(date +'%x %X')   Call: $(print $SUB_PROC_NM | tr 'a-z' 'A-Z')\n"
  print "$(date +'%x %X') Call: ${SUB_PROC_NM}\n"
  print "SEE ORACLE LOG TABLES FOR LOG ENTRIES THAT GO HERE"
  > ${MAIN_LOG_DIR}/${SQL_WRT_LG_FL}
  chmod 666 ${MAIN_LOG_DIR}/${SQL_WRT_LG_FL}

  return 0
} # before_orcl_mod

################################################################################
function after_orcl_mod
{
  # The following variables must be defined in the calling module:
  #   MAIN_LOG_DIR
  #   PROC_TITLE
  #   RETURN_CD
  #   SQL_OUT_LG_FL
  #   SQL_WRT_LG_FL
  #   SUB_PROC_NM

  # The following function must exist in the calling module if $CALL_ERR = "T":
  #   proc_error

  CALL_ERR=${1}
  cat ${MAIN_LOG_DIR}/${SQL_WRT_LG_FL}
  ELAPSED=$(grep Elapsed ${MAIN_LOG_DIR}/${SQL_OUT_LG_FL})
  if [ -n "$ELAPSED" ]; then
    print ${ELAPSED} | sed 's/^/                  /'
  fi

  if [ $RETURN_CD -eq 0 ]; then
    RESULT="0"
  else
    print "  ******* Output from ${SUB_PROC_NM} is below *******"
    sed 's/^/  /g' ${MAIN_LOG_DIR}/${SQL_OUT_LG_FL}
    print "  ******* Output from ${SUB_PROC_NM} is above *******"
    if [ $CALL_ERR = "T" ]; then
      proc_error
    fi
    RESULT="1"
  fi

  srm -sf ${MAIN_LOG_DIR}/${SQL_WRT_LG_FL}
  srm -sf ${MAIN_LOG_DIR}/${SQL_OUT_LG_FL}
# print "\n$(date +'%x %X') ${PROC_TITLE} continuing"
  print "\n${PROC_TITLE}:"
  print "$(date +'%x %X') Continuing after return from ${SUB_PROC_NM}"

  return ${RESULT}
} # after_orcl_mod

################################################################################
function before_sqlp
{
  # The following variables must be defined in the calling module:
  #   MAIN_LOG_DIR
  #   SQL_WRT_LG_FL

  > ${MAIN_LOG_DIR}/${SQL_WRT_LG_FL}
  chmod 666 ${MAIN_LOG_DIR}/${SQL_WRT_LG_FL}

  return 0
} # before_sqlp

################################################################################
function after_sqlp
{
  # The following variables must be defined in the calling module:
  #   MAIN_LOG_DIR
  #   RETURN_CD
  #   SQL_OUT_LG_FL
  #   SQL_WRT_LG_FL if used

  cat ${MAIN_LOG_DIR}/${SQL_WRT_LG_FL} 2> /dev/null

  if [ $RETURN_CD -eq 0 ]; then
    RESULT="0"
  else
    print "  ******* Output from SQL*Plus is below *******"
    sed 's/^/  /g' ${MAIN_LOG_DIR}/${SQL_OUT_LG_FL}
    print "  ******* Output from SQL*Plus is above *******"
    RESULT="1"
  fi

  srm -sf ${MAIN_LOG_DIR}/${SQL_WRT_LG_FL}
  srm -sf ${MAIN_LOG_DIR}/${SQL_OUT_LG_FL}

  return ${RESULT}
} # after_sqlp

################################################################################
function create_spool
{
  # PCI/NFS Migration: To skip use of Oracle UTL_FILE function
  #   This will query data previously written temporarily into IP_LOG_SPOOL
  #   Using Oracle Spool utility, the data will be appended to the specified Unix file
  #   Optionally the data will be deleted from IP_LOG_SPOOL when finished

  #print $(date +'%x %X') "Starting function create_spool"

  if [[ $# -ne 3 ]]
  then
    print $(date +'%x %X') "This function requires 3 parameters"
    print $(date +'%x %X') "     Log/Spool File name, Spool Dir name and delete flag (T/F)"
    print $(date +'%x %X') "Example: 1. $(basename $0) abc.log /opt/ipse/sw1/ips/log T"
    print $(date +'%x %X') "       : 2. $(basename $0) xyz.dat /opt/ipse/sw1/ips/mc/dat F"
    return 1
  fi

  log_file="$1"
  spool_dir="$2"
  delete_fl="$3"

  spool_file=$spool_dir/spool_${log_file}.temp

  #print $(date +'%x %X') "Creating spool file $spool_file for log file $log_file"

  >$spool_file

  if [[ $delete_fl = 'F' ]]; then

    sqlplus -s ${IPSE_USER}/${IPSE_KEY}@$IPSE_SID >/dev/null 2>&1 << EOJ
    WHENEVER OSERROR EXIT FAILURE
    WHENEVER SQLERROR EXIT SQL.SQLCODE
    SET FEEDBACK OFF VERIFY OFF ECHO OFF
    SET HEADING OFF
    SET PAGES 0
    SET COLSEP '|||'
    SET LINESIZE 32767
    SET TRIMSPOOL ON

    SPOOL '$spool_file'

    SELECT spool_msg_txt
    FROM ip_owner.ip_log_spool
    WHERE spool_log_fl_nm = '$log_file'
      AND spool_log_dir_nm = '$spool_dir'
    ORDER BY spool_id;

    SPOOL OFF
    EXIT SQL.SQLCODE
EOJ

  fi

  if [[ $? -ne 0 ]]; then
    #print "$(date +'%x %X') ERROR while processing"
    return 1
  fi

  if [[ $delete_fl = 'T' ]]; then

    sqlplus -s ${IPSE_USER}/${IPSE_KEY}@$IPSE_SID >/dev/null 2>&1 << EOJ
    WHENEVER OSERROR EXIT FAILURE
    WHENEVER SQLERROR EXIT SQL.SQLCODE
    SET FEEDBACK OFF VERIFY OFF ECHO OFF
    SET HEADING OFF
    SET PAGES 0
    SET LINESIZE 32767
    SET TRIMSPOOL ON

    SPOOL '$spool_file'

    SELECT spool_msg_txt
    FROM ip_owner.ip_log_spool
    WHERE spool_log_fl_nm = '$log_file'
      AND spool_log_dir_nm = '$spool_dir'
    ORDER BY spool_id;

    SPOOL OFF

    DELETE FROM ip_owner.ip_log_spool
    WHERE spool_log_fl_nm = '$log_file'
      AND spool_log_dir_nm = '$spool_dir';

    COMMIT;
    EXIT SQL.SQLCODE
EOJ

  fi

  if [[ $? -ne 0 ]]; then
    #print "$(date +'%x %X') ERROR while processing"
    return 1
  fi

  cat ${spool_file} >>${spool_dir}/${log_file}

  srm -sf ${spool_file}
  #print "$(date +'%x %X') Finished processing"
  return 0
} # create_spool

################################################################################
function delete_spool_entry
{
  # PCI/NFS Migration: To skip use of Oracle UTL_FILE function
  #   This will remove specified data from IP_LOG_SPOOL

  #print $(date +'%x %X') "Starting function delete_spool_entry"
  if [[ $# -ne 2 ]]
  then
    print $(date +'%x %X') "This function requires 2 parameters"
    print $(date +'%x %X') "     Log/Spool File name and Spool Dir name"
    print $(date +'%x %X') "Example: 1. $(basename $0) abc.log /opt/ipse/sw1/ips/log"
    print $(date +'%x %X') "       : 2. $(basename $0) xyz.dat /opt/ipse/sw1/ips/mc/dat"
    return 1
  fi

  log_file="$1"
  spool_dir="$2"

  sqlplus -s ${IPSE_USER}/${IPSE_KEY}@$IPSE_SID >/dev/null 2>&1 << EOJ
  WHENEVER OSERROR EXIT FAILURE
  WHENEVER SQLERROR EXIT SQL.SQLCODE
  SET FEEDBACK OFF VERIFY OFF ECHO OFF

  DELETE FROM ip_owner.ip_log_spool
  WHERE spool_log_fl_nm = '$log_file'
    AND spool_log_dir_nm = '$spool_dir';

  COMMIT;
  EXIT SQL.SQLCODE
EOJ

  if [[ $? -ne 0 ]]; then
    #print "$(date +'%x %X') ERROR while processing"
    return 1
  fi

  #print "$(date +'%x %X') Finished processing"
  return 0
} # delete_spool_entry

################################################################################
function create_spool_pgm
{
  # PCI/NFS Migration: To skip use of Oracle UTL_FILE function
  #   This will query data from the logging tables
  #   Using Oracle Spool utility, the data will be appended to the specified Unix file

  #print $(date +'%x %X') "Starting function create_spool_pgm"

  if [[ $# -ne 3 ]]
  then
    print $(date +'%x %X') "This function requires 3 parameters"
    print $(date +'%x %X') "     Log/Spool File name, Spool Dir name and program name"
    print $(date +'%x %X') "Example: 1. $(basename $0) abc.log /opt/ipse/sw1/ips/log LOAD_FX_RATES.SQL"
    print $(date +'%x %X') "       : 2. $(basename $0) xyz.dat /opt/ipse/sw1/ips/mc/dat stat.dat"
    return 1
  fi

  log_file="$1"
  spool_dir="$2"
  pgm_name="$3"

  spool_file=$spool_dir/spool_${log_file}.temp

  #print $(date +'%x %X') "Creating spool file $spool_file for log file $log_file"

  >$spool_file

  sqlplus -s ${IPSE_USER}/${IPSE_KEY}@$IPSE_SID >/dev/null 2>&1 << EOJ
  WHENEVER OSERROR EXIT FAILURE
  WHENEVER SQLERROR EXIT SQL.SQLCODE
  SET FEEDBACK OFF VERIFY OFF ECHO OFF
  SET HEADING OFF
  SET PAGES 0
  SET COLSEP '|||'
  SET LINESIZE 32767
  SET TRIMSPOOL ON

  SPOOL '$spool_file'

  SELECT ilm.msg_txt
  FROM ip_owner.ip_log_msg ilm
  WHERE ilm.job_id = (SELECT ilj.job_id
                      FROM ip_owner.ip_log_job ilj
                      WHERE ilj.job_log_nm = '$log_file'
                        AND ilj.job_log_dir = '$spool_dir')
    AND ilm.pgm_id = (SELECT MAX(ilp.pgm_id)
                      FROM ip_owner.ip_log_pgm ilp
                      WHERE ilp.job_id = ilm.job_id
                        AND ilp.pgm_nm = '$pgm_name')
  ORDER BY ilm.msg_id;

  SPOOL OFF
  EXIT SQL.SQLCODE
EOJ

  if [[ $? -ne 0 ]]; then
    #print "$(date +'%x %X') ERROR while processing"
    return 1
  fi

  cat ${spool_file} >>${spool_dir}/${log_file}

  srm -sf ${spool_file}
  #print "$(date +'%x %X') Finished processing"
  return 0
} # create_spool_pgm

################################################################################
function load_into_spool
{
  # PCI/NFS Migration: To skip use of Oracle UTL_FILE function
  #   This will read from a Unix file and load the lines into IP_LOG_SPOOL

  if [ $# -ne 2 ]; then
    print $(date +'%x %X') "This function requires 2 parameters"
    print $(date +'%x %X') "  Name of file to load, Dir where file is located"
    return 1
  fi

  INPUT_FILE=${1}
  INPUT_DIR=${2}

  while read LN; do

    sqlplus -s ${IPSE_USER}/${IPSE_KEY}@$IPSE_SID >/dev/null 2>&1 << EOJ
    WHENEVER OSERROR EXIT FAILURE
    WHENEVER SQLERROR EXIT SQL.SQLCODE
    SET FEEDBACK OFF VERIFY OFF ECHO OFF
    SET HEADING OFF
    SET PAGESIZE 0
    SET LINESIZE 32767

    logging.log_msg_spool('$INPUT_FILE', '$INPUT_DIR', '$LN');

    EXIT SQL.SQLCODE
EOJ

  done <${INPUT_DIR}/${INPUT_FILE}
  return 0
} # load_into_spool
