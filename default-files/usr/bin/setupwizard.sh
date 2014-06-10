#!/bin/ash
. /lib/functions.sh

# check to see if setupwizard has already been run

# if setup_wizard file does not exist, create it
if [[ ! -f /etc/config/setup_wizard ]]; then
  touch /etc/config/setup_wizard
  
  # indicator for whether setup wizard has already run
  SETUP_RUN=`uci add setup_wizard settings`
  uci rename setup_wizard.$SETUP_RUN=settings
  uci set setup_wizard.settings.enabled=1
  
  # indicator for whether password has been set
  PASSWORD_SET=`uci add setup_wizard uci`
  uci rename setup_wizard.$PASSWORD_SET=passwords
  uci set setup_wizard.passwords.admin_pass=false
fi

echo -e "\n\nWelcome to the configuration wizard.\n"

# if password not set, require password set
if [ `grep root /etc/shadow | cut -d ":" -f 2` == "x" ]; then
  echo "Please choose an administrator password: "
  passwd
  uci set setup_wizard.passwords.admin_pass=changed
fi

# if hostname not changed, allow option to set hostname
if [ !`grep -q \'commotion\' /etc/config/system` ]; then
  while true; do
    echo -e "Set the hostname for this device?"
    read answer
    case $answer in                                            
      [Yy]*  ) echo "Enter new hostname: ";  
            read HOSTNAME;                                
            uci set system.@system[0].hostname=$HOSTNAME;
            break;;                                                                                              
      [Nn]* ) break;;                                          
      * ) echo "Please answer yes[y] or no[n]";;               
    esac 
  done
fi

echo "Please enter mesh network name: "

read MESH_NAME

echo "Please select a valid channel: "

read CHANNEL

echo "Does this mesh network use encryption?"
  while true; do
    read answer                                                
    case $answer in                                            
      [Yy]*  ) echo "Please choose an encryption password: ";  
            read MESH_PASSWORD;                                
            break;;                                                                                          
      [Nn]* ) 
            break;;                                          
      * ) echo "Please answer yes[y] or no[n]";;               
    esac 
  done
  

# SET MESH UCI VALUES

# wireless settings
MESH_CONFIG=`uci add wireless wifi-iface`
uci rename wireless.$MESH_CONFIG=commotionMesh

uci set wireless.commotionMesh.mode=adhoc
uci set wireless.commotionMesh.device=radio0
uci set wireless.commotionMesh.ssid=$MESH_NAME
uci set wireless.commotionMesh.network=$MESH_NAME
uci set wireless.radio0.channel=$CHANNEL
uci set wireless.radio0.disabled=0

# network settings
uci set network.$MESH_NAME=interface
uci set network.$MESH_NAME.class=mesh
uci set network.$MESH_NAME.profile=$MESH_NAME
uci set network.$MESH_NAME.proto=commotion

# firewall settings
uci add_list firewall.@zone[1].network=$MESH_NAME


# SET COMMOTION PROFILE VALUES

commotion new $MESH_NAME
commotion set $MESH_NAME ssid $MESH_NAME
commotion set $MESH_NAME channel $CHANNEL

# SET ENCRYPTION (if any)

if [ $MESH_PASSWORD ]; then
  commotion set $MESH_NAME key $MESH_PASSWORD; 
  uci set wireless.commotionMesh.encryption=psk2;
  uci set wireless.commotionMesh.key=$MESH_PASSWORD;
else
  commotion set $MESH_NAME encryption none
  uci set wireless.commotionMesh.encryption=none
fi


# ACCESS POINT

echo -e "Set up an access point?"
  read answer                                                
  case $answer in                                            
    [Yy]*  ) echo -e "\nAccess point name: "
          read AP_NAME;
          break;;                                            
                                                             
    [Nn]* ) break;;
    * ) echo "Please answer yes[y] or no[n]";;               
  esac 

if [ $AP_NAME ]; then

  # access point encryption
  echo "Would you like to use encryption for the access point?"
    read answer                                                
    case $answer in                                            
      [Yy]*  ) echo "Please choose an encryption password for the AP: ";  
            read AP_PASSWORD;                                
            break;;                                                                                                     
      [Nn]* ) break;;  
      * ) echo "Please answer yes[y] or no[n]";;               
    esac 

  # set AP uci values
  AP_CONFIG=`uci add wireless wifi-iface`
  uci rename wireless.$AP_CONFIG=$AP_NAME

  uci set wireless.$AP_NAME.network=lan
  uci set wireless.$AP_NAME.mode=ap
  uci set wireless.$AP_NAME.ssid=$AP_NAME
  uci set wireless.$AP_NAME.device=radio0
  
  if [ $AP_PASSWORD ]; then
    uci set wireless.$AP_NAME.encryption=psk2;
    uci set wireless.$AP_NAME.key=$AP_PASSWORD;
  else
    uci set wireless.$AP_NAME.encryption=none
  fi
fi
  
# mark changes in setup_wizard config
uci set setup_wizard.settings.enabled=0
uci commit setup_wizard

# commit profile changes
commotion save $MESH_NAME

# commit uci changes
uci commit wireless
uci commit network
uci commit system
uci commit firewall

echo -e "\n\nSettings saved."

echo -e "\n\nCONFIGURATION

NODE SETTINGS
Hostname:               $HOSTNAME

MESH SETTINGS
Mesh name:              $MESH_NAME
Mesh channel:           $CHANNEL
`if [ $MESH_PASSWORD ]; then
  echo -e 
"Mesh encryption:       yes"
else
  echo -e
"Mesh encryption:       no"
fi`

ACCESS POINT SETTINGS"

echo -e "\n\nKeep this configuration?\n\n"

echo -e "\n\nRestarting networking.\n\n"

# restart networking
/etc/init.d/commotiond restart
/etc/init.d/network reload



<<SCRATCH

# call reset_cb first

# then define config_cb() like so:
# loop through all the firewall zones
# find the one with option name 'mesh'
# uci set.cfgstring.network+=mesh
# uci set.cfgstring.network+=$MESH_NAME
# see http://wiik.openwrt.org/doc/devel/config-scripting?s[]=config&s[]=cb

reset_cb

config_cb() {
  local CONFIG_TYPE="$1"
  local CONFIG_NAME="$2"
  
  if [ "$CONFIG_TYPE" == "zone" ]; then
        logger -t setupwizard "Searching config section $CONFIG_TYPE"
    option_cb() {
      local OPTION_NAME="$1"
      local OPTION_VALUE="$2"
        if [ "$OPTION_NAME" == "name" ] && [ "$OPTION_VALUE" == "mesh" ]; then
                logger -t setupwizard "Found mesh zone."
          uci set firewall.$CONFIG_SECTION.network+=$MESH_NAME
          uci set firewall.$CONFIG_SECTION.network+=mesh
        fi
      }
  fi
}
config_load firewall

SCRATCH