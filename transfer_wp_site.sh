#!/usr/bin/env bash

#set -e

# Variables
# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m' 
NC='\033[0m'

url=$1
username=$(echo $url| sed -r 's/-//g'| awk -F. '{print $1}')
root_path="${HOME}/www/${url}"
cpanel_user='test'

# Create ssh key and add to ssh config
echo -e "${BLUE}[-] Creating ssh key and adding it to ssh config${NC}"
ssh_key_file_path="${HOME}/.ssh/${url}_id_rsa"
if [ ! -f $ssh_key_file_path ]; then
	ssh-keygen -N "" -f $ssh_key_file_path
else
	echo -e "${RED}[!] Erorr: ssh key already exists${NC}"
	exit 1
fi

ssh_config_text="\nHost ${url}
	Hostname	92.205.60.148
	IdentityFile	${ssh_key_file_path}
	User		${username}"
echo -e "${ssh_config_text}" >> ~/.ssh/config
ssh-copy-id -i $ssh_key_file_path $url 1>/dev/null 2>/dev/null

echo -e "${GREEN}[+] Success${NC}"

if [ $(find $root_path -name wp-config.php | wc -l) -gt 0 ]; then
	echo -e "${BLUE}[-] Website is wordpress${NC}"
	# Variables
	website_path=$(find $root_path -name wp-config.php | sed 's|\(.*\)/.*|\1|')
	db_name="$(cat $(find $root_path -name wp-config.php -type f) | grep DB_NAME | cut -d \' -f 4)"
	db_new_name="${username}_${db_name}"
	db_user="$(cat $(find $root_path -name wp-config.php -type f) | grep DB_USER | cut -d \' -f 4)"
	db_new_user="${username}_${db_user}"
	db_pass="$(cat $(find $root_path -name wp-config.php -type f) | grep DB_PASSWORD | cut -d \' -f 4)"

	# Database dump
	echo -e "${BLUE}[-] Dumping database${NC}"
	mysqldump -u ${cpanel_user} --no-tablespaces $db_name > "${db_name}.sql"
	echo -e "${GREEN}[+] Success${NC}"

	# Transfer sql file then delete it
	echo -e "${BLUE}[-] Transfering then deleting sql file${NC}"
	scp -q -o LogLevel=QUIET "${db_name}.sql" $url:~/ 
	rm "${db_name}.sql"
	echo -e "${GREEN}[+] Success${NC}"

	# Create database and user in remote host and add password to .my.cnf
	echo -e "${BLUE}[-] Creating database and user and adding password to .my.cnf${NC}"
	ssh $url "echo -e '\n[mysql]\npassword=\"${db_pass}\"' >> ~/.my.cnf"
	ssh $url "uapi Mysql create_database name='${db_new_name}' 1>/dev/null"
	ssh $url "uapi Mysql create_user name='${db_new_user}' password='${db_pass}' 1>/dev/null"
	ssh $url "uapi Mysql set_privileges_on_database user='${db_new_user}' database='${db_new_name}' privileges='ALL PRIVILEGES' 1>/dev/null"
	echo -e "${GREEN}[+] Success${NC}"

	# Import sql file then delete it 
	echo -e "${BLUE}[-] Importing sql file then deleting it${NC}"
	ssh $url "mysql -u $db_new_user -e 'use ${db_new_name}; source /home/${username}/${db_name}.sql;'"
	ssh $url rm "~/${db_name}.sql"
	echo -e "${GREEN}[+] Success${NC}"

else
	echo -e "${BLUE}[-] website is static${NC}"
	website_path=$(find $root_path -name index.html | sed 's|\(.*\)/.*|\1|')
fi

# Transfer web directory
echo -e "${BLUE}[-] Transfering web directory${NC}"
scp -q -o LogLevel=QUIET -r "${website_path}/." "${url}:~/www/"
if [ $(find $root_path -name wp-config.php | wc -l) -gt 0 ]; then
	#ssh $url "sed -i -e 's/$db_pass/${db_new_pass}/g' '/home/${username}/www/wp-config.php'"
	if [ "$db_name" == "$db_user" ]; then
		ssh $url "sed -i -e 's/${db_name}/${db_new_name}/g' '/home/${username}/www/wp-config.php'"
	else
		ssh $url "sed -i -e 's/${db_name}/${db_new_name}/g' '/home/${username}/www/wp-config.php'"
		ssh $url "sed -i -e 's/${db_user}/${db_new_user}/g' '/home/${username}/www/wp-config.php'"
	fi
fi
echo -e "${GREEN}[+] Success${NC}"

# Transfer emails
echo -e "${BLUE}[-] Transfering emails${NC}"
scp -q -o LogLevel=QUIET -r "${HOME}/etc/${url}" "${url}:~/etc"
scp -q -o LogLevel=QUIET -r "${HOME}/mail/${url}" "${url}:~/mail"

echo -e "${GREEN}[+] Success${NC}"

echo -e "${GREEN}[+] Transfer was successful${NC}"
