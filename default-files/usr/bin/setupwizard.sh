#!/bin/ash

# check to see if setupwizard has already been run

clear_previous_configuration() {
  uci delete wireless.commotionMesh
  uci delete wireless.commotionAP
  uci delete network.commotionMesh
   
  uci commit wireless
}

clear_values() {
  unset SETUP_RUN
  unset PASSWORD_SET
  unset HOSTNAME
  unset MESH_NAME
  unset CHANNEL
  unset MESH_PASSWORD
  unset AP_NAME
  unset AP_PASSWORD
  commotion delete $MESH_NAME
}

get_config() {
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
            uci set system.@system[0].hostname="$HOSTNAME";
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
  

# ACCESS POINT

echo -e "Set up an access point?"
  while true; do
  read answer                                                
  case $answer in                                            
    [Yy]* ) echo -e "\nAccess point name: ";
            read AP_NAME;
            break;;                                                                                        
    [Nn]* ) break;;
    * ) echo "Please answer yes[y] or no[n]";;               
  esac 
done

if [ $AP_NAME ]; then

  # access point encryption
  echo "Would you like to use encryption for the access point?"
    while true; do
    read answer                                                
    case $answer in                                            
      [Yy]*  ) echo "Please choose an encryption password for the AP: ";  
            read AP_PASSWORD;                                
            break;;                                                                                                     
      [Nn]* ) break;;  
      * ) echo "Please answer yes[y] or no[n]";;               
    esac 
    done
fi

echo -e "\n\nCONFIGURATION

NODE SETTINGS
Hostname:          "$HOSTNAME"


MESH SETTINGS
SSID:              "$MESH_NAME"
Channel:           "$CHANNEL""
if [ $MESH_PASSWORD ]; then
  echo -e "Encryption:        yes
Password:          "$MESH_PASSWORD""
else
  echo -e "Encryption:        no"
fi

if [ $AP_NAME ]; then

echo -e "\n
ACCESS POINT SETTINGS
SSID:              "$AP_NAME"
Channel:           "$CHANNEL""
fi

if [ $AP_PASSWORD ]; then
  echo -e "Encryption:        yes
Password:          "$AP_PASSWORD""
else
  echo -e "Encryption:        no"
fi

while true; do
echo -e "\n\nKeep this configuration?"
    read answer
    case $answer in                                            
        [Yy]* ) return 0;;                                                                                             
        [Nn]* ) echo "Reverting configuration settings."; 
                clear_values;
                return 1;;                                         
        * )     echo "Please answer yes[y] or no[n]";;               
    esac 
  done
}


set_config() {

# SET MESH UCI VALUES

# wireless settings
MESH_CONFIG=`uci add wireless wifi-iface`
uci rename wireless."$MESH_CONFIG"=commotionMesh

uci set wireless.commotionMesh.mode=adhoc
uci set wireless.commotionMesh.device=radio0
uci set wireless.commotionMesh.ssid="$MESH_NAME"
uci set wireless.commotionMesh.network="$MESH_NAME"
uci set wireless.radio0.channel="$CHANNEL"
uci set wireless.radio0.disabled=0

# network settings
uci set network.commotionMesh=interface
uci set network.commotionMesh.class=mesh
uci set network.commotionMesh.profile="$MESH_NAME"
uci set network.commotionMesh.proto=commotion

# firewall settings
uci add_list firewall.@zone[1].network="$MESH_NAME"


# SET COMMOTION PROFILE VALUES

commotion new "$MESH_NAME"
commotion set "$MESH_NAME" ssid "$MESH_NAME"
commotion set "$MESH_NAME" channel "$CHANNEL"

# SET ENCRYPTION (if any)

if [ $MESH_PASSWORD ]; then
  commotion set "$MESH_NAME" key "$MESH_PASSWORD"; 
  uci set wireless.commotionMesh.encryption=psk2;
  uci set wireless.commotionMesh.key="$MESH_PASSWORD";
else
  commotion set "$MESH_NAME" encryption none
  uci set wireless.commotionMesh.encryption=none
fi


# SET AP SETTINGS
if [ $AP_NAME ]; then
  # set AP uci values
  AP_CONFIG=`uci add wireless wifi-iface`
  uci rename wireless."$AP_CONFIG"=commotionAP

  uci set wireless.commotionAP.network=lan
  uci set wireless.commotionAP.mode=ap
  uci set wireless.commotionAP.ssid="$AP_NAME"
  uci set wireless.commotionAP.device=radio0
  
  if [ $AP_PASSWORD ]; then
    uci set wireless.commotionAP.encryption=psk2;
    uci set wireless.commotionAP.key="$AP_PASSWORD";
  else
    uci set wireless.commotionAP.encryption=none
  fi
fi

  
# mark changes in setup_wizard config
uci set setup_wizard.settings.enabled=0
uci commit setup_wizard

# commit profile changes
commotion save "$MESH_NAME"

# commit uci changes
uci commit wireless
uci commit network
uci commit system
uci commit firewall

echo -e "\n\nSettings saved."

echo -e "\n\nRestarting networking.\n\n"

# restart networking
/etc/init.d/commotiond restart
/etc/init.d/network reload
}

if [ `uci get setup_wizard.settings.enabled` == 0 ]; then
  echo -e "Setup Wizard has already been run."
while true; do
echo -e "\n\nSet new configuration?"
    read answer
    case $answer in                                            
        [Yy]* ) echo -e "Reverting previous configuration.";
                clear_previous_configuration;
                break;;                                                                                              
        [Nn]* ) echo "Keeping settings. Closing Setup Wizard."; 
                exit 0;;                                          
        * )     echo "Please answer yes[y] or no[n]";;               
    esac 
  done
fi

# RUN SETUP WIZARD
get_config 

# if user rejects settings, rerun get_config
while [ $? -eq 1 ]; do                                                                                                                                
  get_config                                                                                                                                                                                                                                                                                                                                  
done 

# if user accepts settings, set the configuration
if [ $? -eq 0 ]; then
  set_config
fi