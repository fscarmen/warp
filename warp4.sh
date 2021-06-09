##### 为 IPv6 only VPS 添加 WGCF，IPv4走 warp #####
##### KVM 属于完整虚拟化的 VPS 主机，网络性能方面：内核模块＞wireguard-go。#####

# 判断系统，安装差异部分

# Debian 运行以下脚本
if grep -q -E -i "debian" /etc/issue; then
	
	# 更新源
	apt update

	# 添加 backports 源,之后才能安装 wireguard-tools 
	apt -y install lsb-release sudo
	echo "deb http://deb.debian.org/debian $(lsb_release -sc)-backports main" | tee /etc/apt/sources.list.d/backports.list

	# 再次更新源
	apt update

	# 安装一些必要的网络工具包和wireguard-tools (Wire-Guard 配置工具：wg、wg-quick)
	sudo apt -y --no-install-recommends install net-tools iproute2 openresolv dnsutils wireguard-tools linux-headers-$(uname -r)
	
	# 安装 wireguard 内核模块
	sudo apt -y --no-install-recommends install wireguard-dkms
	
# Ubuntu 运行以下脚本
     elif grep -q -E -i "ubuntu" /etc/issue; then

	# 更新源
	apt update

	# 安装一些必要的网络工具包和 wireguard-tools (Wire-Guard 配置工具：wg、wg-quick)
	apt -y --no-install-recommends install net-tools iproute2 openresolv dnsutils wireguard-tools sudo

# CentOS 运行以下脚本
     elif grep -q -E -i "kernel" /etc/issue; then

	# 安装一些必要的网络工具包和wireguard-tools (Wire-Guard 配置工具：wg、wg-quick)
	yum -y install epel-release sudo
	sudo yum -y install net-tools wireguard-tools

	# 安装 wireguard 内核模块
	sudo curl -Lo /etc/yum.repos.d/wireguard.repo https://copr.fedorainfracloud.org/coprs/jdoss/wireguard/repo/epel-7/jdoss-wireguard-epel-7.repo
	sudo yum -y install epel-release wireguard-dkms

	# 升级所有包同时也升级软件和系统内核
	sudo yum -y update
	
	# 添加执行文件环境变量
        export PATH=$PATH:/usr/local/bin

# 如都不符合，提示,删除临时文件并中止脚本
     else 
	# 提示找不到相应操作系统
	echo -e "\033[32m 抱歉，我不认识此系统！\033[0m"
	
	# 删除临时目录和文件，退出脚本
	rm -f warp*
	exit 0

fi

# 判断系统架构是 AMD 还是 ARM，虚拟化是 LXC 还是 KVM,设置应用的依赖与环境
if [[ $(hostnamectl) =~ .*arm.* ]]
  then architecture=arm64
  else architecture=amd64
fi

# 以下为3类系统公共部分

# 安装 wgcf
sudo wget -nc -6 -O /usr/local/bin/wgcf https://github.com/ViRb3/wgcf/releases/download/v2.2.3/wgcf_2.2.3_linux_$architecture

# 添加执行权限
sudo chmod +x /usr/local/bin/wgcf

# 注册 WARP 账户 (将生成 wgcf-account.toml 文件保存账户信息)
echo | wgcf register
until [ $? -eq 0 ]  
  do
   echo | wgcf register
done


# 生成 Wire-Guard 配置文件 (wgcf-profile.conf)
wgcf generate
until [ $? -eq 0 ]  
  do
   wgcf generate
done

# 修改配置文件 wgcf-profile.conf 的内容,使得 IPv4 的流量均被 WireGuard 接管，让 IPv4 的流量通过 WARP IPv6 节点以 NAT 的方式访问外部 IPv4 网络
sudo sed -i '/\:\:\/0/d' wgcf-profile.conf | sudo sed -i 's/engage.cloudflareclient.com/[2606:4700:d0::a29f:c001]/g' wgcf-profile.conf

# 把 wgcf-profile.conf 复制到/etc/wireguard/ 并命名为 wgcf.conf
sudo cp wgcf-profile.conf /etc/wireguard/wgcf.conf

# 删除临时文件
rm -f warp* wgcf*

# 自动刷直至成功（ warp bug，有时候获取不了ip地址）
wg-quick up wgcf
wget -qO- ipv4.ip.sb
until [ $? -eq 0 ]  
  do
   wg-quick down wgcf
   wg-quick up wgcf
   wget -qO- ipv4.ip.sb
done

# 启用 Wire-Guard 网络接口守护进程
sudo systemctl start wg-quick@wgcf

# 设置开机启动
sudo systemctl enable wg-quick@wgcf

# 优先使用 IPv4 网络
grep -qE '^[ ]*precedence[ ]*::ffff:0:0/96[ ]*100' /etc/gai.conf || echo 'precedence ::ffff:0:0/96  100' | sudo tee -a /etc/gai.conf

# 结果提示
echo -e "\033[32m 恭喜！为 IPv6 only VPS 添加 warp 已成功，IPv4地址为:$(wget -qO- ipv4.ip.sb) \033[0m"