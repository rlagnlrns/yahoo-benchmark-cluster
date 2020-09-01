#!/bin/bash

git clone https://github.com/yahoo/streaming-benchmarks.git
sudo yum install wget -y
wget http://mirror.apache-kr.org/maven/maven-3/3.6.3/binaries/apache-maven-3.6.3-bin.tar.gz -P /tmp
sudo tar xf /tmp/apache-maven-3.6.3-bin.tar.gz -C /opt
sudo ln -s /opt/apache-maven-3.6.3 /opt/maven
#echo 로 높은 root 권한 파일에 쓰기명령어
echo "export M2_HOME=/opt/maven" | sudo tee -a /etc/profile.d/maven.sh
echo "export MAVEN_HOME=/opt/maven" | sudo tee -a /etc/profile.d/maven.sh
echo "export PATH=${M2_HOME}/bin:${PATH}" | sudo tee -a /etc/profile.d/maven.sh
sudo chmod +x /etc/profile.d/maven.sh
source /etc/profile.d/maven.sh
wget https://raw.githubusercontent.com/technomancy/leiningen/stable/bin/lein
chmod +x lein
echo "export LEIN_HOME=/home/jinhuijun" >> .bash_profile
echo "export PATH=\$PATH:\$LEIN_HOME:" >> .bash_profile
source .bash_profile
lein
#./streaming-benchmarks/stream-bench.sh SETUP
#./streaming-benchmarks/stream-bench.sh SPARK_TEST
