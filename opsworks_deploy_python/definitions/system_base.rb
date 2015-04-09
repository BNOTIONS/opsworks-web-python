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

  apt_package "ossec-agent" do
    action :install
  end
end
