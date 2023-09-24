#!/bin/bash
#Todo
#backup
#frontend script?
#
#check if not root
if (( $(id -u $USER) == 0 ));then echo "Dont run this script with root" && exit 1;fi
cd $(dirname $0)

PKGinstallCheck() {
	local cancel="echo all needed PKG installed"
	for PKG in "docker" "sed" "curl" "netstat" "jq"
	do
		whereis $PKG > /dev/null 2> /dev/null
		if (( $? != 0 ));then
			echo "$PKG missing"
			cancel="exit 1"
		fi
	done
	$cancel
}
PKGinstallCheck

dockCon="mcdocker"
wd="~/Projekte/cpp/mcserver/build"

build() {
# Def on build?! - build will done only for the first boot/script start?!
	### check for missing pkgs
	mkdir -p /tmp/$dockCon

	###Docker
	#curl -s https://github.com/alpinelinux/docker-alpine/raw/a29a148442aa2d6d13d3d87b224d058ec951ad46/x86_64/alpine-minirootfs-3.15.0_alpha20210804-x86_64.tar.gz -o /tmp/$dockCon/alpine-minirootfs-3.15.0_alpha20210804-x86_64.tar.gz
	#echo "FROM scratch" > /tmp/$dockCon/Dockerfile
	#echo "ADD alpine-minirootfs-3.15.0_alpha20210804-x86_64.tar.gz /" >> /tmp/$dockCon/Dockerfile
	#echo 'CMD ["/bin/sh"]' >> /tmp/$dockCon/Dockerfile

	echo "FROM alpine:edge" > /tmp/$dockCon/Dockerfile
	echo "RUN apk update" >> /tmp/$dockCon/Dockerfile
	echo 'RUN for i in 8 11 16 17; do apk add openjdk${i}-jre && ln -s /usr/lib/jvm/java-${i}-openjdk/bin/java /usr/bin/java${i};done' >> /tmp/$dockCon/Dockerfile
	echo "RUN apk add git make gcc-gdc" >> /tmp/$dockCon/Dockerfile
	echo "RUN git clone https://github.com/Tiiffi/mcrcon.git && make -C mcrcon && mv mcrcon/mcrcon /usr/bin/ && rm -rf mcrcon" >> /tmp/$dockCon/Dockerfile
	echo "RUN apk del git make gcc-gdc" >> /tmp/$dockCon/Dockerfile
	echo "WORKDIR /minecraft" >> /tmp/$dockCon/Dockerfile

	docker build /tmp/$dockCon -t $dockCon > /dev/null

	rm -rf /tmp/$dockCon/

	mkdir -p $wd/standalone
	local ipRange="172."$(($(docker network inspect $(docker network ls -f driver=bridge --format {{.Name}})|jq -r ".[].IPAM.Config[].Subnet"|cut -d . -f 2|sort|tail -1)+1))".0"
	docker network create ${dockCon}_standalone --attachable --subnet $ipRange.0/16 > /dev/null
}

getJavaVersion() {
	local mcversion=$1
	local v=0
	if (( $(echo $mcversion|cut -d . -f 1 ) == 1 ));then
		if (( $(echo $mcversion|cut -d . -f 2 ) < 12 ));then v=8;fi
		if (( $(echo $mcversion|cut -d . -f 2 ) < 16 ));then v=11;fi
		if (( $(echo $mcversion|cut -d . -f 2 ) == 16 ));then
				if (( $(echo $mcversion|cut -d . -f 3 ) < 5 ));then v=11;else v=16;fi
		fi
		if (( $(echo $mcversion|cut -d . -f 2 ) > 16 ));then v=17;fi
	fi
	echo $v
}

getJavaVersion2() {
	local file=$1
	local mcversion=$2
	local output=$(unzip -p $file version.json|jq ".java_version")
	if [[ $output == "caution: filename not matched:  version.json" ]];then
		echo $(getJavaVersion ${mcversion})
}

mcrconfun() {
	local netname=$1
	local sername=$2
	local mccmd=$3
	local ip=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${dockCon}_${netname}_${sername})

	docker run --rm --name ${dockCon}_${netname}_${sername}_mcrcon --network ${dockCon}_${netname} -t -i $dockCon sh -c "mcrcon -H $ip -p password $mccmd"
}

genStartStop() {
	local netname=$1
	local sername=$2
	local mcv=$3
	local javaargs=$4
	local startfile=$5
	local getPlayerCMD=$6
	local msgcmd=$7
	local stopcmd=$8

	#gen start.sh
	#jv=$(getJavaVersion $mcv)
	jv=$(getJavaVersion2 $wd/$netname/$sername/$startfile $mcv)
	if (( $jv == 0 ));then exit 1;fi
	echo "#!/bin/sh" > $wd/$netname/$sername/start.sh
	echo 'cd $(realpath $(dirname $0))' >> $wd/$netname/$sername/start.sh
	echo "java$jv $javaargs -jar $startfile --nogui" >> $wd/$netname/$sername/start.sh
	chmod +x $wd/$netname/$sername/start.sh

	#gen stop.cmd
	echo '# '$getPlayerCMD > $wd/$netname/$sername/stop.cmd
	local sec=(10 10 5 1 1 1 1 1 0)
	local leftsec=$(($(echo ${sec[@]}|tr " " "+")))
	for i in ${sec[@]}; do
		echo '> '$msgcmd' [{"text":"[","color":"dark_gray","bold":true},{"text":"'$netname'","color":"gold"},{"text":"] ","color":"dark_gray"},{"text":"'$sername' stop in '$leftsec's","color":"white","bold":false}]' >> $wd/$netname/$sername/stop.cmd
		echo '$ sleep '$i >> $wd/$netname/$sername/stop.cmd
		sec=$(($leftsec-$i))
	done
	echo '> '$stopcmd >> $wd/$netname/$sername/stop.cmd
}

#> tellraw @a [{"text":"[","color":"dark_gray","bold":true},{"text":"AaGeWa","color":"gold"},{"text":"] ","color":"dark_gray"},{"text":"Server stop in 30s","color":"white","bold":false}]

crSerScript() {
	local netname=$1 #string
	local sername=$2 #sting
	local maxPlayer=$3 #int
	local version=$4 #string
	local dUser=$5 #int
	local playercmd=$6

	mkdir -p $wd/$netname/$sername/plugins

	# Download newest build of the version from https://papermc.io/
	#local paperv=$(curl -s https://papermc.io/api/v2/projects/paper/versions/$version|cut -d ] -f 1|rev|cut -d , -f 1|rev)
	local paperv=$(curl -s https://papermc.io/api/v2/projects/paper/versions/$version|jq -r ".builds[-1]")
	curl -s https://papermc.io/api/v2/projects/paper/versions/$version/builds/$paperv/downloads/paper-$version-$paperv.jar -o $wd/$netname/$sername/paper-$version-$paperv.jar

	echo "#Minecraft server properties" >> $wd/$netname/$sername/server.properties
	echo "allow-flight=true" >> $wd/$netname/$sername/server.properties
	echo "difficulty=normal" >> $wd/$netname/$sername/server.properties
	echo "max-players=$maxPlayer" >> $wd/$netname/$sername/server.properties
	echo "enable-rcon=true" >> $wd/$netname/$sername/server.properties
	echo "rcon.password=password" >> $wd/$netname/$sername/server.properties

	# gen start file
	genStartStop $netname $sername $version "-Xmx1G -Xms512M" "paper-*.jar" "$playercmd" "telltraw @a" "stop"

	docker run --rm -u $dUser --name ${dockCon}_${netname}_${sername}_servercr -v $wd/$netname/$sername:/minecraft -ti $dockCon ./start.sh > /dev/null
	#docker wait ${dockCon}_${netname}_${sername}_servercr
	sed -i "s/eula=false/eula=true/" $wd/$netname/$sername/eula.txt
}

startSerScript() {
	local netname=$1 #string
	local sername=$2 #string
	local dUser=$3 #int
	local args
	local ARGS

	# Check if MariaDB is needed and isn't already running. Starting when it isn't running.
	if [ "$netname" != "standalone" ] && [ "$(grep 'SQL:' $wd/$netname/.network.cfg|awk '{print $2}')" = "true" ] && [ "$(docker ps --format {{.Names}} -f name=$dockCon|grep ${dockCon}_${netname}_mariadb -wc)" = "0" ];then
		local ipRange=$(grep ipRange $wd/$netname/.network.cfg|awk '{print $2}'|cut -d . -f -3)
		docker run --rm --name ${dockCon}_${netname}_mariadb -v $wd/$netname/.mysql/var:/var/lib/mysql -v $wd/$netname/.mysql/my.cnf.d:/etc/my.cnf.d -u $dUser --network ${dockCon}_${netname} --ip $ipRange.15 -e MYSQL_ROOT_PASSWORD="password" -d mariadb > /dev/null
		sleep 5
	fi

	for ARGS in $(grep "$sername:" $wd/$netname/.servers.cfg|awk '{print $2}');do
		args="$args $(echo $ARGS|tr '^' ' ')"
	done
	docker run --rm -u $dUser -v $wd/$netname/$sername:/minecraft --name ${dockCon}_${netname}_${sername} $args -tid $dockCon ./start.sh > /dev/null
}

stopSerScript() {
	local netname=$1
	local sername=$2

	#echo $(head -1 $wd/$netname/$sername/stop.cmd|grep "#"|cut -d " " -f 2-)
	#echo $(mcrconfun $netname $sername "$(head -1 $wd/$netname/$sername/stop.cmd|grep '#'|cut -d ' ' -f 2-)")
	if [ "$(echo $(head -1 $wd/$netname/$sername/stop.cmd)|awk '{print $1}')" = "#" ] && [ $(echo $(mcrconfun $netname $sername "$(echo $(head -1 $wd/$netname/$sername/stop.cmd)|cut -d ' ' -f 2-)|")|awk '{print $4}') = 0 ]; then
		local stopcmd=$(tail -1 $wd/$netname/$sername/stop.cmd|awk '{print $2}')
		#echo "$(tail -1 $wd/$netname/$sername/stop.cmd|awk '{print $2}')"|socat EXEC:"docker attach ${dockCon}_${netname}_${sername}",pty STDIN
		mcrconfun $netname $sername "$stopcmd"
	else
		while read -r line;do
			#echo $line
			#echo ${line:0:1}
			#echo ${line:1}
			if [ "${line:0:1}" = "$" ];then
				$(${line:1})
			elif [ "${line:0:1}" = ">" ];then
				#echo "${line:1}" | socat EXEC:"docker attach ${dockCon}_${netname}_${sername}",pty STDIN
				echo mcrconfun $netname $sername "$(echo ${line:1})" #the input device is not a tty - err msg
				mcrconfun $netname $sername ${line:1} #the input device is not a tty - err msg
			elif [ "${line:0:1}" != "#" ];then
				echo "...unknown command"
			fi
		done < "$wd/$netname/$sername/stop.cmd"
	fi
	docker wait ${dockCon}_${netname}_${sername}
	if [ "$netname" != "standalone" ] && [ "$(docker ps --format {{.Names}} -f name=${dockCon}_${netname})" = "${dockCon}_${netname}_mariadb" ];then
		docker stop ${dockCon}_${netname}_mariadb
	fi
}

backupScript() {
	local netname=$1
	local sername=$2
	local day=$(date +%d.%m.$%y)
	#local ip=docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${dockCon}_${netname}_${sername}
	local world=$(grep "level-name=" $wd/$netname/$sername/server.properties|cut -d = -f 2)

	if (( $(docker ps --format {{.Names}}|grep ${dockCon}_${netname}_${sername} -wc) == 1 )) && [ $sername != "proxy" ];then

		if [ ! -d $wd/.backup/$netname/$sername ];then mkdir -p $wd/.backup/$netname/$sername;fi

		mcrconfun $netname $sername "-w 5 save-off save-all"
		sleep 60
		cd $wd/$netname/$sername
		zip -r $world-$day.zip $(ls --color=no|grep $world)
		mcrconfun $netname $sername "save-on"

		gzip $world-$day.zip
		mv $world-$day.zip.gz $wd/.backup/$netname/$sername
	fi
}

crMariadb() {
	local netname=$1 #string
	local duser=$2 #int
	local ip=$3 #string

	mkdir -p $wd/$netname/.mysql/var
	mkdir -p $wd/$netname/.mysql/my.cnf.d
	docker run --rm --name ${dockCon}_${netname}_mariadb -v $wd/$netname/.mysql/var:/var/lib/mysql -v $wd/$netname/.mysql/my.cnf.d:/etc/my.cnf.d -u $duser --network ${dockCon}_${netname} --ip $ip -e MYSQL_ROOT_PASSWORD="password" -d mariadb > /dev/null
	#sleep 5 # no sleep -_-
	#docker run --rm --name ${dockCon}_${netname}_mariadbcr -u $duser --network ${dockCon}_${netname} -tid mariadb "mysql -h $ip -u root --password=password -e 'CREATE DATABASE minecraft;'" > /dev/null
}

crNetwork() {
	local netname=$1 # string
	local port=$2 # int
	local maxPlayer=$3 # int
	local version=$4 # string
	local duser=$5 # int (uuid)
	local plugins=$6 #string

	#echo "##########"
	#echo "Create Minecraft Network:"
	#echo "  Name: $netname"
	#echo "  Where:  $wd"
	#echo "  Version: $version"
	#echo "  Listening: 0.0.0.0:$port"
	#echo "  LuckPerms: $lp"
	#echo "##########"

	mkdir -p $wd/$netname/proxy/plugins

	#plugin for rcon support in bungeecord
	#cd $wd/$netname/proxy/plugins
	#wget https://github.com/orblazer/bungee-rcon/releases/download/v1.0.0/bungee-rcon-1.0.0.jar > /dev/null
	cp $wd/pluginInstaller/data/bungee-rcon-1.0.0.jar $wd/$netname/proxy/plugins

	#docker network create ${dockCon}_$netname -d overlay --attachable > /dev/null
	local ipRange="172."$(($(docker network inspect $(docker network ls -f driver=bridge --format {{.Name}})|jq -r ".[].IPAM.Config[].Subnet"|cut -d . -f 2|sort|tail -1)+1))".0"
	docker network create ${dockCon}_$netname --attachable --subnet $ipRange.0/16 > /dev/null

	#create network.cfg file
	echo "version: $version" > $wd/$netname/.network.cfg
	echo "dockerUser: $duser" >> $wd/$netname/.network.cfg
	echo "ipRange: $ipRange.0/16" >> $wd/$netname/.network.cfg
	echo "plugins: $plugins" >> $wd/$netname/.network.cfg

	echo "proxy:" "--network^${dockCon}_${netname}" > $wd/$netname/.servers.cfg
	echo "proxy: --ip^$ipRange.10" >> $wd/$netname/.servers.cfg
	echo "proxy: -p^$port:25577" >> $wd/$netname/.servers.cfg

	#download newest build of the choosed version from https://papermc.io/downloads
	local basev=$(echo $version|cut -d . -f -2)
	local wfallv=$(	curl -s "https://papermc.io/api/v2/projects/waterfall/versions/$basev"|jq ".builds[-1]")
			curl -s "https://papermc.io/api/v2/projects/waterfall/versions/$basev/builds/$wfallv/downloads/waterfall-$basev-$wfallv.jar" -o $wd/$netname/proxy/waterfall-$basev-$wfallv.jar


	#crSerScript $netname "lobby" $maxPlayer $version $duser "mcrconfun $netname lobby list|awk '{print \$2}'"
	crSerScript $netname "lobby" $maxPlayer $version $duser "list|awk '{print \$2}'"
	echo "lobby:" "--network^${dockCon}_${netname}" >> $wd/$netname/.servers.cfg
	echo "lobby:" "--ip^$ipRange.20" >> $wd/$netname/.servers.cfg

	# gen start file
	#genStartStop $netname "proxy" $version "-Xmx512M -Xms512M -XX:+UseG1GC -XX:G1HeapRegionSize=4M -XX:+UnlockExperimentalVMOptions -XX:+ParallelRefProcEnabled -XX:+AlwaysPreTouch" "waterfall-$basev-$wfallv.jar" "mcrconfun $netname proxy glist|grep players|awk '{print \$4}'" "alertraw" "end"
	genStartStop $netname "proxy" $version "-Xmx512M -Xms512M -XX:+UseG1GC -XX:G1HeapRegionSize=4M -XX:+UnlockExperimentalVMOptions -XX:+ParallelRefProcEnabled -XX:+AlwaysPreTouch" "waterfall-*.jar" "glist|grep players|awk '{print \$4}'" "alertraw" "end"

	local needSQL="false"

	for plugs in $plugins;do
		local plugname=$(echo $plugs|cut -d "^" -f 1)
		local plugargs=$(echo $plugs|cut -d "^" -f 2-)
		source $wd/pluginInstaller/install/${plugname}Proxy.sh
	done

	if [ $needSQL = "true" ];then #$needSQL will be set true in the pluginsInstaller if needed
		crMariadb $netname $duser $ipRange.15
	fi
	echo "SQL: $needSQL" >> $wd/$netname/.network.cfg
	echo "perms: $Perms" >> $wd/$netname/.network.cfg

	#docker run --rm --name ${dockCon}_${netname}_mariadb -v $wd/$netname/.mysql/var:/var/lib/mysql -v $wd/$netname/.mysql/my.cnf.d:/etc/my.cnf.d -u $duser --network ${dockCon}_${netname} --ip $ipRange.15 -e MYSQL_ROOT_PASSWORD="password" -d mariadb > /dev/null

	# generate proxy and lobby config files
	startSerScript $netname "proxy" $duser
	startSerScript $netname "lobby" $duser
	while [ "$(mcrconfun $netname lobby 'stop 2> /dev/null')" = "" ];do docker wait ${dockCon}_${netname}_lobby_mcrcon 2> /dev/null;done
	#mcrconfun $netname "proxy" "end > /dev/null"
	echo "end"|socat EXEC:"docker attach ${dockCon}_${netname}_proxy",pty STDIN
	docker wait ${dockCon}_${netname}_proxy 2> /dev/null

	#proxy config
	#sed -i "s/max_players: 1/max_players: $maxPlayer/" $wd/$netname/proxy/config.yml
	#sed -i "s/ip_forward: false/ip_forward: true/" $wd/$netname/proxy/config.yml
	#sed -i "s/- admin/- default/" $wd/$netname/proxy/config.yml
	#sed -i "s/address: localhost:25565/address: $ipRange.20:25565/" $wd/$netname/proxy/config.yml
	#sed -i "s/motd: '&1Another Bungee server'/motd: \"\&2Network \&8of\\\\n\&6\&n${netname}\"/" $wd/$netname/proxy/config.yml
	#sed -i "s/motd: '&1Just another Waterfall - Forced Host'/motd: \"\&2Lobby \&8of\\\\n\&6\&n${netname}\"/" $wd/$netname/proxy/config.yml
	#sed -i "s/game_version: ''/game_version: \'$version\'/" $wd/$netname/proxy/waterfall.yml

	#lobby config
	#sed -i "s/bungeecord: false/bungeecord: true/" $wd/$netname/lobby/spigot.yml
	#sed -i "s/keep-spawn-loaded: true/keep-spawn-loaded: false/" $wd/$netname/lobby/spigot.yml
	sed -i "s/online-mode=true/online-mode=false/" $wd/$netname/lobby/server.properties

	yq -i -y ".listeners[].max_players |= ${maxPlayer}" $wd/$netname/proxy/config.yml
	yq -i -y ".listeners[].motd |= \"&2Network &8of\n&6&n${netname}\"" $wd/$netname/proxy/config.yml
	yq -i -y ".ip_forward |= true" $wd/$netname/proxy/config.yml
	yq -i -y ".groups.md_5[] |= \"default\"" $wd/$netname/proxy/config.yml
	yq -i -y ".servers.lobby.address |= \"${ipRange}.20:25565\"" $wd/$netname/proxy/config.yml
	yq -i -y ".servers.lobby.motd |= \"&2Lobby &8of\n&6&n${netname}\"" $wd/$netname/proxy/config.yml
	yq -i -y ".game_version |= \"${version}\"" $wd/$netname/proxy/waterfall.yml
	yq -i -y ".settings.bungeecord |= true" $wd/$netname/lobby/spigot.yml
	yq -i -y ".settings.\"keep-spawn-loaded\" |= false" $wd/$netname/lobby/spigot.yml

	for plugs in $plugins;do
		local plugname=$(echo $plugs|cut -d "^" -f 1)
		local plugargs=$(echo $plugs|cut -d "^" -f 2-)
		source $wd/pluginInstaller/config/${plugname}Proxy.sh
	done

	if [ $needSQL = "true" ];then
		docker stop ${dockCon}_${netname}_mariadb > /dev/null
		docker wait ${dockCon}_${netname}_mariadb 2> /dev/null
	fi
}

addNetServer() {
	local netname=$1 #string
	local sername=$2 #string
	local maxPlayer=$3 #int

	local version=$(grep "version:" $wd/$netname/.network.cfg|awk '{print $2}')
	local duser=$(grep "dockerUser:" $wd/$netname/.network.cfg|awk '{print $2}')
	local ipRange=$(grep "ipRange:" $wd/$netname/.network.cfg|awk '{print $2}'|cut -d . -f -3)
	local ip=$ipRange.$(($(grep "address: $ipRange" $wd/$netname/proxy/config.yml|cut -d ":" -f 2|cut -d . -f 4|sort|tail -1)+1))
	local plugins=$(grep "plugins:" $wd/$netname/.network.cfg|cut -d " " -f 2-)

	#crSerScript $netname $sername $maxPlayer $version $duser "mcrconfun $netname $sername list|awk '{print \$2}'"
	crSerScript $netname $sername $maxPlayer $version $duser "list|awk '{print \$2}'"

	echo "$sername:" "--network^${dockCon}_${netname}" >> $wd/$netname/.servers.cfg
	echo "$sername:" "--ip^$ip" >> $wd/$netname/.servers.cfg

	for plugs in $plugins;do
		local plugname=$(echo $plugs|cut -d "^" -f 1)
		local plugargs=$(echo $plugs|cut -d "^" -f 2-)
		source $wd/pluginInstaller/install/${plugname}Server.sh
	done

	startSerScript $netname $sername $duser
	while [ "$(mcrconfun $netname $sername 'stop 2> /dev/null')" = "" ];do docker wait ${dockCon}_${netname}_${sername}_mcrcon 2> /dev/null;done
	docker wait ${dockCon}_${netname}_${sername}

	for plugs in $plugins;do
		local plugname=$(echo $plugs|cut -d "^" -f 1)
		local plugargs=$(echo $plugs|cut -d "^" -f 2-)
		source $wd/pluginInstaller/config/${plugname}Server.sh
	done

	#proxy config
	#echo "  ${sername}:" >> $wd/$netname/proxy/config.yml
	#echo "    motd: \"&2"$sername" Server &8of\\\n&6&n"$netname"\"" >> $wd/$netname/proxy/config.yml
	#echo "    address: ${ip}:25565" >> $wd/$netname/proxy/config.yml
	#echo "    restricted: ${Perms:-false}" >> $wd/$netname/proxy/config.yml

	yq -i -y ".servers += {\"${sername}\"}, .servers.${sername} |= {\"motd\":\"&2${sername} &8of\n&6&n${netname}\"} + {\"address\":\"${ip}:25565\"} + {\"restricted\":${Perms:-false}}" $wd/$netname/proxy/config.yml

	#server config
	#sed -i "s/bungeecord: false/bungeecord: true/" $wd/$netname/$sername/spigot.yml
	sed -i "s/online-mode=true/online-mode=false/" $wd/$netname/$sername/server.properties
	yq -i -y ".settings.bungeecord |= true" $wd/$netname/$sername/spigot.yml

}

getPort() {
	local netname=$1 #string

	#local port=$(cat $wd/standalone/.servers.cfg 2> /dev/null |awk '{print $2}'|sort|tail -1)
	local port=$(($(grep "\-p^" $wd/$netname/.servers.cfg|cut -d : -f 2|cut -d "^" -f 2|sort|tail -1)+1))
	local port=${port:-30000}

	while (( $(netstat -ntl|grep -wc $port) >= 1 )); do port=$(($port+1)); done
	echo $port
}

crServer() {
	local sername=$1 #string
	local maxPlayer=$2 #int
	local version=$3 #string
	local duser=$4 #int

	mkdir -p $wd/standalone/$sername/plugins

	local port=$(getPort "standalone")
	echo ${sername}: "-p^$port:25565" >> $wd/standalone/.servers.cfg
	#crSerScript "standalone" $sername $maxPlayer $version $duser "mcrconfun standalone $sername list|awk '{print \$2}'"
	crSerScript "standalone" $sername $maxPlayer $version $duser "list|awk '{print \$2}'"
}

delNetwork() {
	local netname=$1
	docker stop $(docker ps -f name="${dockCon}_${netname}" --format {{.Names}})
	rm -rf $wd/$netname
	docker network rm ${dockCon}_${netname}
}
delServer() {
	netname=$1
	sername=$2
	#docker stop ${dockCon}_${netname}_${sername}

	if [ "$(docker ps -f name=${dockCon}_${netname}_${sername} --format {{.Names}})" = "${dockCon}_${netname}_${sername}" ];then
		echo "Server is running, stop it first, befor you remove it"
		exit 1
	fi

	rm -rf $wd/$netname/$sername
	#for i in $(grep -w $sername: $wd/$netname/proxy/config.yml|grep -w "restricted" -B 6|tr " " "^") ;do
	#	string=$(echo $string|tr "^" " ")
	#	sed -i /$string/d $wd/$netname/proxy/config.yml
	#done
	sed -i /$sername:/d $wd/$netname/.servers.cfg
	if [ "$netname" != "standalone" ];then yq -i -y "del(.servers.$sername)" $wd/$netname/proxy/config.yml;fi

}

#build
#crNetwork "mcnet" "25599" "64" "1.17.1" "1000" "false" "false"
#crServer "joshi" "4" "1.18.1" "1000"
#startSerScript "standalone" "joshi" "1000"

#crNetwork "AaGeWa" "25565" "16" "1.18" "1000" "luckperms GeyserMC^19133"
#crNetwork "test_118" "25533" "16" "1.18" "1000"
#delNetwork "AaGeWa"

#addNetServer "AaGeWa" "hardcore" "8"
#addNetServer "test_118" "main" "16"
#delServer "test_118" "main"

#docker run --rm --name ${dockCon}_test_118_mariadb -v $wd/mcnet/.mysql/var:/var/lib/mysql -v $wd/test_118/.mysql/my.cnf.d:/etc/my.cnf.d -u 1000 --network ${dockCon}_test_118 --ip 172.23.0.15 -e MYSQL_ROOT_PASSWORD="password" -d mariadb > /dev/null #&& sleep 15

#startSerScript "test_118" "proxy" "1000"
#startSerScript "test_118" "lobby" "1000"
#startSerScript "test_118" "main" "1000"

#stopSerScript "test_118" "proxy"

startSerScript "AaGeWa" "proxy" "1000"
#startSerScript "AaGeWa" "lobby" "1000"
#startSerScript "AaGeWa" "mainAaGeWa" "1000"
#startSerScript "AaGeWa" "main" "1000"
#startSerScript "AaGeWa" "stoneattack" "1000"
#startSerScript "AaGeWa" "nameless" "1000"
#startSerScript "AaGeWa" "hardcore" "1000"
#startSerScript "AaGeWa" "darkRPG" "1000"

#stopSerScript "AaGeWa" "proxy"
#stopSerScript "AaGeWa" "lobby"
#stopSerScript "AaGeWa" "main"
#stopSerScript "AaGeWa" ""


#startSerScript "mcnet" "proxy" "1000"
#startSerScript "mcnet" "lobby" "1000"
#startSerScript "mcnet" "main" "1000"
#startSerScript "mcnet" "authLobby" "1000"

#crServer "niceToHave" 8 "1.17.1" 1000
#startSerScript "standalone" "niceToHave" "1000"

#> tellraw @a [{"text":"[","color":"dark_gray","bold":true},{"text":"AaGeWa","color":"gold"},{"text":"] ","color":"dark_gray"},{"text":"Server stop in 30s","color":"white","bold":false}]

#startSerScript "mcnet" "proxy" "1000"
#startSerScript "mcnet" "lobby" "1000"

#stopSerScript "mcnet" "lobby"
#stopSerScript "mcnet" "proxy"

gui() {
	echo "What do you want do"
	echo "  build : Run only for on time after installed the script"
	echo "  mkNetwork : Make a Server Network with Waterfall (fork of Bungeecord)"
	echo "  addNetwork : Add a Server to a specific Minecraft Network"
	echo "  mkServer : Make a Standalone Server"
	echo "  startNetwork :"
	read -p ""
}
