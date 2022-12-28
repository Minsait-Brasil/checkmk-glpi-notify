#!/bin/bash
# GLPI Automation Script
# Bulk        : no
#
# Script Name : check_mk_glpi-notify.sh
# Describe    : Automação de chamado do check_mk para glpi
# Author      : Minsait Brasil | Hermirio Dos Santos, Wanderson and Pedro Bandeira Da Silva, Mateus
# Version     : v1.1
# Dependencies: curl, jq
# =====================================================================================================

#source varhost

INFO=($NOTIFY_PARAMETERS)
if [[ ${#INFO[@]} -lt 7 ]]
then
    echo "variável não encontrada"
else
    GLPI_URL=$NOTIFY_PARAMETER_1
    GLPI_USER_TOKEN=$NOTIFY_PARAMETER_2
    GLPI_APP_TOKEN=$NOTIFY_PARAMETER_3
    CHECKMK_URL=$NOTIFY_PARAMETER_4
    ID_GROUP=$NOTIFY_PARAMETER_5
    ID_USER=$NOTIFY_PARAMETER_6
    TAG=$NOTIFY_PARAMETER_7
    ROW=($(sed 's/ /_/g; s/,/ /g' <<< $NOTIFY_PARAMETER_8))
    for ITLS in ${ROW[@]}
    do
        AUX1=$(grep -o ${ITLS} <<< $NOTIFY_HOSTGROUPNAMES)
        if [[ ${ITLS} == $AUX1 ]] 
        then
            TAG="$NOTIFY_PARAMETER_7-$AUX1"
            break
        fi
        AUX2=$(grep -o ${ITLS} <<< $NOTIFY_SERVICEGROUPNAMES)
        if [[ ${ITLS} == $AUX2 ]] 
        then
            TAG="$NOTIFY_PARAMETER_7-$AUX2"
            break
        fi
    done
fi
SITE=$NOTIFY_OMD_SITE


#Criar um token de sessão para conexão
function _get_init_session()
{
    TOKEN_SESSION=`
    curl --silent \
        --request GET \
        --url http://$GLPI_URL/apirest.php/initSession/ \
        --header "App-Token: $GLPI_APP_TOKEN" \
        --header "Authorization: Basic $GLPI_USER_TOKEN" \
        --header 'Content-Type: application/json' | jq ".session_token" | sed 's/"//g'`
}

#Encerrar conexão da sessão
function _close_session()
{
    curl --silent \
         --request GET \
         --header 'Content-Type: application/json' \
         --url "http://$GLPI_URL/apirest.php/killSession/" \
         --header "App-Token: $GLPI_APP_TOKEN"  \
         --header "Session-Token: $TOKEN_SESSION"
}

#Criar um chamado
function _create_ticket()
{
    if [[ -z $1 && -z $2 ]]
    then
        ID_GROUPS=$ID_GROUP
        curl -s --request POST \
             --url "http://$GLPI_URL/apirest.php/Ticket?=" \
             --header 'Content-Type: application/json' \
             --header "App-Token: $GLPI_APP_TOKEN" \
             --header "Authorization: Basic $GLPI_USER_TOKEN" \
             --header "Session-Token: $TOKEN_SESSION" \
             --data '{
                "input":{
                    "name": "'"$TITLE"'",
                    "content": "'"$MSG"'",
                    "urgency": 5,
                    "priority": 5,
                    "_users_id_requester": "'$ID_USER'",
                    "_groups_id_assign": ['$ID_GROUPS']
                }
            }'
        echo "GLPI: Ticket $TITLE created"
    else
        ID_GROUPS=$(echo "$ID_GROUP,$1")
        curl -s --request POST \
            --url "http://$GLPI_URL/apirest.php/Ticket?=" \
            --header 'Content-Type: application/json' \
            --header "App-Token: $GLPI_APP_TOKEN" \
            --header "Authorization: Basic $GLPI_USER_TOKEN" \
            --header "Session-Token: $TOKEN_SESSION" \
            --data '{
                "input":{
                    "name": "'"$TITLE"'",
                    "content": "'"$MSG"'",
                    "urgency": 5,
                    "priority": 5,
                    "_users_id_requester": "'$ID_USER'",
                    "_groups_id_assign": ['$ID_GROUPS'],
                    "itilcategories_id": '$2'
                }
            }'
        echo "GLPI: Ticket $TITLE created"
    fi
}

#Pegar o id do chamado
function _get_id()
{
    IFS=''
    curl -s \
           --request GET \
           --url "http://$GLPI_URL/apirest.php/search/Ticket/?is_deleted=0&criteria[0][field]=12&criteria[0][searchtype]=equals&criteria[0][value]=notold&criteria[1][link]=AND&criteria[1][field]=5&criteria[1][searchtype]=equals&criteria[1][value]=$ID_USER&range=0-200" \
	       --header "App-Token: $GLPI_APP_TOKEN" \
	       --header "Authorization: Basic $GLPI_USER_TOKEN" \
	       --header "Session-Token: $TOKEN_SESSION" | jq '.data[] | select(.["12"] <= 2) | select(.["1"]=="'$TITLE'" ) | .["2"]'
}
#Adiciona uma mensagem de acompanhamento
function _add_follow_up()
{
    ID=$1
    curl -s --request POST \
        --url "http://$GLPI_URL/apirest.php/Ticket/$ID/ITILFollowup/?=" \
        --header 'Content-Type: application/json' \
        --header "Authorization: Basic $GLPI_USER_TOKEN" \
        --header "App-Token: $GLPI_APP_TOKEN" \
        --header "Session-Token: $TOKEN_SESSION" \
        --data '{
            "input":{
                "items_id": "'$ID'",
                "content": "'"$MSG"'",
                "solutiontypes": "2",
                "itemtype": "Ticket"
            }
        }'
    echo "GLPI: Ticket $TITLE updated $ID"
}

#encerra o chamado
function _close_ticket()
{
    ID=$1
    curl -s --request POST \
        --url "http://$GLPI_URL/apirest.php/Ticket/$ID/ITILSolution/?=" \
        --header 'Content-Type: application/json' \
        --header "Authorization: Basic $GLPI_USER_TOKEN" \
        --header "App-Token: $GLPI_APP_TOKEN" \
        --header "Session-Token: $TOKEN_SESSION" \
        --data '{
            "input":{
                "items_id": "'$ID'",
                "content": "'"$MSG"'",
                "solutiontypes": "2",
                "itemtype": "Ticket"
            }
        }' 1> /dev/null
    echo "GLPI: Ticket $TITLE closed"
}
#Pegar o id do grupo
function _get_id_group()
{
    IFS=''
    curl -s --request GET \
        --url "http://$GLPI_URL/apirest.php/Group/?&range=0-200" \
        --header "App-Token: $GLPI_APP_TOKEN" \
        --header "Authorization: Basic $GLPI_USER_TOKEN" \
        --header "Session-Token: $TOKEN_SESSION" | jq '.[] | select(.name=="'$GROUP_NAME'") | .id'
}

#Pegar o id da categoria
function _get_id_itilcategorie()
{
    IFS=''
    curl -s --request GET \
        --url "http://$GLPI_URL/apirest.php/Itilcategory/?&range=0-200" \
        --header "App-Token: $GLPI_APP_TOKEN" \
        --header "Authorization: Basic $GLPI_USER_TOKEN" \
        --header "Session-Token: $TOKEN_SESSION" | jq '.[] | select(.name=="'$CATEGORIE_NAME'") | .id'
}

#Pegar o id da maquina
function _get_id_computer()
{
    curl -s --request GET \
        --url "http://$GLPI_URL/apirest.php/Computer/?&range=0-1000" \
        --header "App-Token: $GLPI_APP_TOKEN" \
        --header "Authorization: Basic $GLPI_USER_TOKEN" \
        --header "Session-Token: $TOKEN_SESSION" | jq '.[] | select(.name=="'$NOTIFY_HOSTNAME'") | .id'

}

#Atribuir ticket a um computador
function _assign_computer()
{
    TICKET_ID=$1
    COMPUTER_ID=$2
    curl --request POST \
        --url "http://$GLPI_URL/apirest.php/Ticket/$TICKET_ID/Item_ticket/" \
        --header "App-Token: $GLPI_APP_TOKEN" \
        --header "Authorization: Basic $GLPI_USER_TOKEN" \
        --header 'Content-Type: application/json' \
        --header "Session-Token: $TOKEN_SESSION" \
        --data '{
        	"input":{
        		"items_id":"'$COMPUTER_ID'",
        		"itemtype":"Computer",
        		"tickets_id": "'$TICKET_ID'"
        	}
        }'

}

function main()
{
    case "$NOTIFY_NOTIFICATIONTYPE" in
        PROBLEM)
            case "${NOTIFY_WHAT::4}" in
                HOST)
                    case "$NOTIFY_HOSTSTATE" in
                        UNREACH)
                            TITLE="[$TAG] $NOTIFY_HOSTNAME DOWN"
                            case "$NOTIFY_LASTHOSTSTATE" in
                                DOWN)
                                    TITLE="[$TAG] $NOTIFY_HOSTNAME DOWN"
                                    _get_init_session
                                    if [[ -z `_get_id` ]]
                                    then
                                        TITLE="[$TAG] $NOTIFY_HOSTNAME $NOTIFY_HOSTSTATE"
                                        MSG="Problem started: $NOTIFY_LONGDATETIME \n \
                                        Host: $NOTIFY_HOSTNAME \n \
                                        Hostgroup: $NOTIFY_HOSTGROUPNAMES \n \
                                        Severity: $NOTIFY_HOSTSTATE \n \
                                        Problem: $NOTIFY_HOSTOUTPUT \n \
                                        Check MK URL: http://$CHECKMK_URL/$SITE/$NOTIFY_HOSTURL"
                                        _create_ticket
                                        if [[ -z `_get_id_computer` ]]
                                        then
                                            echo "GLPI: Ticket $TITLE created(no item to assign)"    
                                        
                                        else
                                            _assign_computer `_get_id` `_get_id_computer` 1> /dev/null
                                            echo "GLPI: Ticket $TITLE created (computer $NOTIFY_HOSTNAME assigned)"
                                        fi
                                    else
                                        MSG="Problem updated: $NOTIFY_LONGDATETIME \n \
                                        Host: $NOTIFY_HOSTNAME \n \
                                        Condition: $NOTIFY_HOSTOUTPUT \n \
                                        Severity update: From $NOTIFY_LASTHOSTSTATE to $NOTIFY_HOSTSTATE"
                                        _add_follow_up `_get_id`
                                       
                                    fi
                                     _close_session
                                    ;;
                                UNREACH)
                                    echo "GLPI: Existing ticket $TITLE"
                                    ;;
                                *)
                                    _get_init_session
                                    TITLE="[$TAG] $NOTIFY_HOSTNAME $NOTIFY_HOSTSTATE"
                                    MSG="Problem started: $NOTIFY_LONGDATETIME \n \
                                    Host: $NOTIFY_HOSTNAME \n \
                                    Hostgroup: $NOTIFY_HOSTGROUPNAMES \n \
                                    Severity: $NOTIFY_HOSTSTATE \n \
                                    Problem: $NOTIFY_HOSTOUTPUT \n \
                                    Check MK URL: http://$CHECKMK_URL/$SITE/$NOTIFY_HOSTURL"
                                    _create_ticket                                    
                                    if [[ -z `_get_id_computer` ]]
                                    then
                                        echo "GLPI: Ticket $TITLE created(no item to assign)"
                                    
                                    else 
                                        _assign_computer `_get_id` `_get_id_computer` 1> /dev/null
                                        echo "GLPI: Ticket $TITLE created(computer $NOTIFY_HOSTNAME assigned)"
                                    fi
                                    _close_session
                                    ;;
                                        
                            esac
                            ;;
                        DOWN)
                            case $NOTIFY_LASTHOSTSTATE in
                                UNREACH)
                                    
                                    TITLE="[$TAG] $NOTIFY_HOSTNAME DOWN"
                                    _get_init_session
                                    if [[ -z `_get_id` ]]
                                    then
                                        TITLE="[$TAG] $NOTIFY_HOSTNAME $NOTIFY_HOSTSTATE"
                                        MSG="Problem started: $NOTIFY_LONGDATETIME \n \
                                        Host: $NOTIFY_HOSTNAME \n \
                                        Hostgroup: $NOTIFY_HOSTGROUPNAMES \n \
                                        Severity: $NOTIFY_HOSTSTATE \n \
                                        Problem: $NOTIFY_HOSTOUTPUT \n \
                                        Check MK URL: http://$CHECKMK_URL/$SITE/$NOTIFY_HOSTURL"
                                        _create_ticket                                        
                                        if [[ -z `_get_id_computer` ]]
                                        then
                                            echo "GLPI: Ticket $TITLE created(no item to assign)"
                                        
                                        else
                                            _assign_computer `_get_id` `_get_id_computer` 1> /dev/null
                                            echo "GLPI: Ticket $TITLE created(computer $NOTIFY_HOSTNAME assigned)"
                                        fi
                                    else
                                        MSG="Problem started: $NOTIFY_LONGDATETIME \n \
                                        Host: $NOTIFY_HOSTNAME \n \
                                        Condition: $NOTIFY_HOSTOUTPUT \n \
                                        Severity update: From $NOTIFY_LASTHOSTSTATE to $NOTIFY_HOSTSTATE"
                                        _add_follow_up `_get_id`
                                       
                                    fi
                                     _close_session
                                    ;;
                                
                                *)
                                    _get_init_session
                                    TITLE="[$TAG] $NOTIFY_HOSTNAME $NOTIFY_HOSTSTATE"
                                    if [[ -z `_get_id` ]]
                                    then
                                        TITLE="[$TAG] $NOTIFY_HOSTNAME $NOTIFY_HOSTSTATE"
                                        MSG="Problem started: $NOTIFY_LONGDATETIME \n \
                                        Host: $NOTIFY_HOSTNAME \n \
                                        Hostgroup: $NOTIFY_HOSTGROUPNAMES \n \
                                        Severity: $NOTIFY_HOSTSTATE \n \
                                        Problem: $NOTIFY_HOSTOUTPUT \n \
                                        Check MK URL: $CHECKMK_URL/$NOTIFY_HOSTURL"
                                        _create_ticket                                        
                                        if [[ -z `_get_id_computer` ]]
                                        then
                                            echo "GLPI: Ticket $TITLE created(no item to assign)"    
                                        
                                        else
                                            _assign_computer `_get_id` `_get_id_computer` 1> /dev/null
                                            echo "GLPI: Ticket $TITLE created(computer $NOTIFY_HOSTNAME assigned)"
                                        fi
                                    else
                                        echo "GLPI: Existing ticket $TITLE"
                                    fi
                                    _close_session
                                    ;;          
                            esac            
                            ;;
						UP)
                            _get_init_session
                            TITLE="[$TAG] $NOTIFY_HOSTNAME DOWN"
                            if [[ -z `_get_id` ]]
                            then
                                echo "GLPI: host $NOTIFY_HOSTNAME UP $NOTIFY_NOTIFICATIONTYPE"
                            else
                                MSG="Solved problem: $NOTIFY_LONGDATETIME \n \
                                Hostgroup: $NOTIFY_HOSTGROUPNAMES \n \
                                Host: $NOTIFY_HOSTNAME is $NOTIFY_HOSTSTATE \n \
                                Condition: $NOTIFY_HOSTOUTPUT \n \
                                ticket closed automatically"
                                _close_ticket `_get_id`
                            fi
                            _close_session
                            ;;
                    esac
                    ;;
                SERV)
                    [[ "$NOTIFY_SERVICEDESC" == "Check_MK" ]] && echo "GLPI: Service Check_MK disabled Ticket not created" && exit 0
		            [[ "$NOTIFY_SERVICEDESC" == "Check_MK Discovery" ]] && echo "GLPI: Service Check_MK Discovery disabled Ticket not created" && exit 0
                    case "$NOTIFY_SERVICESTATE" in
                        CRITICAL)
                            TITLE="[$TAG] $NOTIFY_HOSTNAME $NOTIFY_SERVICEDESC $NOTIFY_SERVICESTATE"
                            case "$NOTIFY_LASTSERVICESTATE" in
                                WARNING)
                                    _get_init_session
                                    if [[ -z `_get_id` ]]
                                    then  
                                        MSG="Problem started: $NOTIFY_LONGDATETIME \n \
                                        Host: $NOTIFY_HOSTNAME \n \
                                        Service: $NOTIFY_SERVICEDESC \n \
                                        Severity: $NOTIFY_SERVICESTATE \n \
                                        Problem: $NOTIFY_SERVICEOUTPUT \n \
                                        Check MK URL: http://$CHECKMK_URL/$SITE/$NOTIFY_SERVICEURL"
                                        _create_ticket                                        
                                        if [[ -z `_get_id_computer` ]]
                                        then
                                            echo "GLPI: Ticket $TITLE created(no item to assign)"    
                                        
                                        else
                                            _assign_computer `_get_id` `_get_id_computer` 1> /dev/null
                                            echo "GLPI: Ticket $TITLE created (computer $NOTIFY_HOSTNAME assigned)"
                                        fi
                                    else
                                        MSG="Problem started: $NOTIFY_LONGDATETIME \n \
                                        Host: $NOTIFY_HOSTNAME \n \
                                        Service: $NOTIFY_SERVICEDESC \n \
                                        Condition: $NOTIFY_SERVICEOUTPUT \n \
                                        Severity update: From $NOTIFY_LASTSERVICESTATE to $NOTIFY_SERVICESTATE"
                                        _add_follow_up `_get_id`
                                    fi
                                    _close_session
                                    ;;
                                *)
                                    _get_init_session
                                    if [[ -z `_get_id` ]]
                                    then
                                        MSG="Problem started: $NOTIFY_LONGDATETIME \n \
                                        Host: $NOTIFY_HOSTNAME \n \
                                        Service: $NOTIFY_SERVICEDESC \n \
                                        Severity: $NOTIFY_SERVICESTATE \n \
                                        Problem: $NOTIFY_SERVICEOUTPUT \n \
                                        Check MK URL: http://$CHECKMK_URL/$SITE/$NOTIFY_SERVICEURL"
                                         _create_ticket                                        
                                        if [[ -z `_get_id_computer` ]]
                                        then
                                            echo "GLPI: Ticket $TITLE created(no item to assign)"
                                        
                                        else
                                            _assign_computer `_get_id` `_get_id_computer` 1> /dev/null
                                            echo "GLPI: Ticket $TITLE created (computer $NOTIFY_HOSTNAME assigned)"
                                        fi
                                    else
                                        echo "GLPI: Existing ticket $TITLE"
                                    fi 
                                    _close_session
                                    ;;
                            esac        
                            _get_init_session
                            ;;
                        WARNING)
                            TITLE="[$TAG] $NOTIFY_HOSTNAME $NOTIFY_SERVICEDESC CRITICAL"
                            _get_init_session
                            if [[ -z `_get_id` ]]
                            then
                                echo "GLPI: Service $NOTIFY_SERVICESTATE Ticket not created"
                            else
                                MSG="Problem started: $NOTIFY_LONGDATETIME \n \
                                Host: $NOTIFY_HOSTNAME \n \
                                Service: $NOTIFY_SERVICEDESC \n \
                                Condition: $NOTIFY_SERVICEOUTPUT \n \
                                Severity update: From $NOTIFY_LASTSERVICESTATE to $NOTIFY_SERVICESTATE"
                                _add_follow_up `_get_id`

                            fi
                            _close_session
                            ;;
						
                        OK)  
                            TITLE="[$TAG] $NOTIFY_HOSTNAME $NOTIFY_SERVICEDESC CRITICAL"
                            _get_init_session
                            if [[ -z `_get_id` ]]
                            then
                                echo "GLPI: Service $NOTIFY_SERVICESTATE Ticket not created"

                            else
                                MSG="Solved problem: $NOTIFY_LONGDATETIME \n \
                                Host: $NOTIFY_HOSTNAME \n \
                                Service: $NOTIFY_SERVICEDESC is $NOTIFY_SERVICESTATE \n \
                                Condition: $NOTIFY_SERVICEOUTPUT \n \
                                ticket closed automatically"
                                _close_ticket `_get_id`
                            fi
                            _close_session
                            ;;
                    esac
                    ;;
            esac
            ;;
        ACKNOWLEDGEMENT)
            case "${NOTIFY_WHAT::4}" in
                HOST)
                    _get_init_session
                    TITLE="[$TAG] $NOTIFY_HOSTNAME down"
                    if [[ -z `_get_id` ]]
                    then
                        echo "GLPI: There is no ticket"
                    else
                        MSG="$NOTIFY_HOSTACKAUTHOR acknowledged and commented problem at $NOTIFY_LONGDATETIME \n \
                        Commented: $NOTIFY_HOSTACKCOMMENT"
                        _add_follow_up `_get_id`

                    fi
                    _close_session
                    ;;
                SERV)
                    _get_init_session
                    TITLE="[$TAG] $NOTIFY_HOSTNAME $NOTIFY_SERVICEDESC $NOTIFY_SERVICESTATE"
                    if [[ -z `_get_id` ]]
                    then
                        echo "GLPI: There is no ticket"
                    else
                        MSG="$NOTIFY_SERVICEACKAUTHOR acknowledged and commented problem at $NOTIFY_LONGDATETIME \n \
                        Commented: $NOTIFY_SERVICEACKCOMMENT"
                        _add_follow_up `_get_id`
                    fi
                    _close_session
                    ;;
            esac
            ;;
        *)
            case "${NOTIFY_WHAT::4}" in
                HOST)
                    case "$NOTIFY_HOSTSTATE" in
                        UP)
                            _get_init_session
                            TITLE="[$TAG] $NOTIFY_HOSTNAME DOWN"
                            if [[ -z `_get_id` ]]
                            then
                                echo "GLPI: Host $NOTIFY_HOSTNAME UP $NOTIFY_NOTIFICATIONTYPE"
                            else
                                MSG="Solved problem: $NOTIFY_LONGDATETIME \n \
                                Hostgroup: $NOTIFY_HOSTGROUPNAMES \n \
                                Host: $NOTIFY_HOSTNAME is $NOTIFY_HOSTSTATE \n \
                                Condition: $NOTIFY_SERVICEOUTPUT \n \
                                ticket closed automatically"
                                _close_ticket `_get_id`
                            fi
                            _close_session
                            ;;
                    esac
                    ;;
                SERV)
                    case "$NOTIFY_SERVICESTATE" in 
                        OK)  
                            TITLE="[$TAG] $NOTIFY_HOSTNAME $NOTIFY_SERVICEDESC CRITICAL"
                            _get_init_session
                            if [[ -z `_get_id` ]]
                            then
                                echo "GLPI: Service $NOTIFY_SERVICESTATE Ticket not created"

                            else
                                MSG="Solved problem: $NOTIFY_LONGDATETIME \n \
                                Host: $NOTIFY_HOSTNAME \n \
                                Service: $NOTIFY_SERVICEDESC is $NOTIFY_SERVICESTATE \n \
                                Condition: $NOTIFY_SERVICEOUTPUT \n \
                                ticket closed automatically"
                                _close_ticket `_get_id`
                            fi
                            _close_session
                            ;;
                    esac
                    ;;
            esac
            ;;
    esac
}
main
