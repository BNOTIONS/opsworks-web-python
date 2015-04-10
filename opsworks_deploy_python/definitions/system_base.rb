define :system_base_setup do
  deploy = params[:deploy_data]
  application = params[:app_name]
  
  apt_repository 'ossec' do
    uri 'http://ossec.wazuh.com/repos/apt/ubuntu'
    components ['main']
    distribution 'trusty'
    key 'http://ossec.wazuh.com/repos/apt/conf/ossec-key.gpg.key'
    action :add
  end

  apt_package "ossec-hids-agent" do
    action :install
  end

  template "/var/ossec/etc/ossec.conf" do
        source "ossec.conf.erb"
        cookbook 'opsworks_deploy_python'
        owner "root"
        group "ossec"
        mode 0440
        variables({
          :ossecserverip => '184.94.59.178',
          :deploy => deploy,
          :application => application
        })
  end

  execute "/var/ossec/bin/agent-auth -m 184.94.59.178 -p 1515" do
    not_if {::File.exists?("/var/ossec/etc/client.keys")}
  end

  service "ossec" do
    action :restart
  end
end
