#
# Cookbook Name:: opsworks_deploy_python
# Recipe:: default
#
node[:deploy].each do |application, deploy|
  system_base_setup do
    deploy_data deploy
    app_name application
  end
end
