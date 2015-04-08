define :django_setup do
  deploy = params[:deploy_data]
  application = params[:app_name]

  python_base_setup do
    deploy_data deploy
    app_name application
  end

  # Merge gunicorn settings hashes
  gunicorn = Hash.new
  gunicorn.update node["deploy_django"]["gunicorn"] || {}
  gunicorn.update deploy["django_gunicorn"] || {}
  node.normal[:deploy][application]["django_gunicorn"] = gunicorn

  if gunicorn["enabled"]
    python_pip "gunicorn" do
      virtualenv ::File.join(deploy[:deploy_to], 'shared', 'env')
      user deploy[:user]
      group deploy[:group]
      action :install
    end
  end

  celery = Hash.new
  celery.update node["deploy_django"]["celery"] || {}
  celery.update deploy["django_celery"] || {}
  node.normal[:deploy][application]["django_celery"] = celery

end

define :django_configure do
  deploy = params[:deploy_data]
  application = params[:app_name]
  run_action = params[:run_action] || :restart

  # Make sure we have up to date attribute settings
  deploy = node[:deploy][application]

  # We only want to run this after the deploy has run, configure also
  # runs before deploy.  We need to check if the deploy has run by
  # checking for the deploy dir, but also checking a flag in case the
  # resources have been collected, but not created
  if deploy[:deploy_to] && (node[:deploy][application]["initially_deployed"] || ::File.exist?(deploy[:deploy_to]))
    django_cfg = ::File.join(deploy[:deploy_to], 'current', Helpers.django_setting(deploy, 'settings_file', node))
    # Create local config settings
    template django_cfg do
      source Helpers.django_setting(deploy, 'settings_template', node) || "settings.py.erb"
      cookbook deploy["django_settings_cookbook"] || 'opsworks_deploy_python'
      owner deploy[:user]
      group deploy[:group]
      mode 0644
      variables Hash.new
      variables.update deploy
      variables.update :django_database => Helpers.django_setting(deploy, 'database', node)
    end
    
    gunicorn = Hash.new
    gunicorn.update node["deploy_django"]["gunicorn"] || {}
    gunicorn.update deploy["django_gunicorn"] || {}
    node.normal[:deploy][application]["django_gunicorn"] = gunicorn
    
    if gunicorn["enabled"]
      include_recipe 'supervisor'
      include_recipe 'logrotate'
      base_command = "#{::File.join(deploy[:deploy_to], 'shared', 'env', 'bin', 'gunicorn')} --pythonpath=#{::File.join(deploy[:deploy_to], 'current', deploy[:app_module])}"
      
      gunicorn_cfg = ::File.join(deploy[:deploy_to], 'shared', 'gunicorn_config.py')
      gunicorn_command = "#{base_command} --error-logfile=- --access-logfile=/var/log/supervisor/#{application}_access.log --access-logformat='%%({X-Forwarded-For}i)s %%(l)s %%(u)s %%(t)s \"%%(r)s\" %%(s)s %%(b)s \"%%(f)s\" \"%%(a)s\"' -c #{gunicorn_cfg} wsgi:application"
      
      gunicorn_config gunicorn_command do
        owner deploy[:user]
        group deploy[:group]
        path  gunicorn_cfg
        listen "#{gunicorn["host"]}:#{gunicorn["port"]}"
        backlog gunicorn["backlog"]
        worker_processes gunicorn["workers"]
        worker_class gunicorn["worker_class"]
        worker_max_requests gunicorn["max_requests"]
        worker_timeout gunicorn["timeout"]
        worker_keepalive gunicorn["keepalive"]
        preload_app gunicorn["preload_app"]
        action :create
      end
      
      supervisor_service application do
        action :enable
        environment deploy[:environment] || gunicorn["environment"] || {}
        command gunicorn_command
        directory ::File.join(deploy[:deploy_to], "current")
        autostart true
        user deploy[:user]
      end
      
      supervisor_service application do
        action :nothing
        only_if "sleep 60"
        subscribes :restart,  "gunicorn_config[#{gunicorn_command}]", :delayed
        subscribes :restart,  "template[#{django_cfg}]", :delayed
      end

      s3rotatescript = "/etc/#{application}/archive_logs.sh"
      s3rotatedir = "/etc/#{application}"

      directory s3rotatedir do
        owner "root"
        group "root"
      end

      template s3rotatescript do
        source "archive_logs.sh.erb"
        cookbook deploy["django_settings_cookbook"] || 'opsworks_deploy_python'
        owner "root"
        group "root"
        mode 0755
        variables({
          :application => application
        })
      end

      shutdownhook = "/etc/init/shutdown-hook.conf"

      template shutdownhook do
        source "shutdown-hook.conf.erb"
        cookbook deploy["django_settings_cookbook"] || 'opsworks_deploy_python'
        owner "root"
        group "root"
        mode 0644
        variables({
          :application => application
        })
      end

      logrotate_app application do
        path      '/var/log/supervisor/*.log'
        options   ['missingok', 'delaycompress', 'notifempty']
        frequency 'daily'
        rotate    30
        create    '644 root adm'
        sharedscripts true
        enable true
        postrotate "/bin/bash /etc/#{application}/upload_log_to_s3.sh log.1"
      end
    end
    
    celery = Hash.new
    celery.update node["deploy_django"]["celery"] || {}
    celery.update deploy["django_celery"] || {}
    node.normal[:deploy][application]["django_celery"] = celery
    
    if celery["djcelery"] && celery["enabled"]
      django_djcelery do
        deploy_data node[:deploy][application]
        app_name application
      end
    elsif celery["enabled"]
      django_celery do
        deploy_data node[:deploy][application]
        app_name application
      end
    end
    if run_action
      supervisor_service application do
        action run_action
      end
    end
  end
end
