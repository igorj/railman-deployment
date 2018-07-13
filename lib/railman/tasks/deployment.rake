desc 'Setup rails application for the first time on a server'
task :setup do
  on roles(:all) do
    with fetch(:environment) do
      if test "[ -d #{fetch(:deploy_to)} ]"
        invoke :fetch_and_reset_git_repository
      else
        execute :git, :clone, fetch(:repo_url), fetch(:deploy_to)
        invoke :sync_local_dirs_to_server
      end
      server_conf_dir = "#{fetch(:deploy_to)}/config/server"
      execute :su_cp, "#{server_conf_dir}/puma.service /lib/systemd/system/#{fetch(:application)}.service"
      execute :su_cp, "#{server_conf_dir}/sidekiq.service /lib/systemd/system/#{fetch(:application)}_sidekiq.service"
      execute :su_ln, "-s -f #{server_conf_dir}/logrotate.conf /etc/logrotate.d/#{fetch(:application)}"
      within fetch(:deploy_to) do
        upload! './config/master.key', "#{fetch(:deploy_to)}/config/master.key"
        execute :bundle, :install, '--without development test'
        invoke :create_database_from_sql_file
        execute :rake, 'assets:precompile'
        execute :systemctl, 'daemon-reload'
        execute :systemctl, :start, fetch(:application)
        execute :systemctl, :start, "#{fetch(:application)}_sidekiq"
        execute :systemctl, :enable, fetch(:application)
        execute :systemctl, :enable, "#{fetch(:application)}_sidekiq"
        # copy temporary simple nginx.conf only for getting letsencrypt certificate
        nginx_conf = File.read(File.join(File.dirname(__FILE__), 'nginx.conf'))
        nginx_conf.gsub!('DOMAINS', fetch(:domains).join(' '))
        nginx_conf.gsub!('APPLICATION', fetch(:application))
        upload! StringIO.new(nginx_conf), "#{fetch(:deploy_to)}/tmp/nginx.conf"
        execute :su_cp, "#{fetch(:deploy_to)}/tmp/nginx.conf /etc/nginx/conf.d/#{fetch(:application)}.conf"
        execute :systemctl, :restart, :nginx
        execute :certbot, "certonly --webroot -w /home/deploy/apps/#{fetch(:application)}/public #{fetch(:domains).collect { |d| '-d ' + d }.join(' ')} -n --agree-tos -m #{fetch(:certbot_email)} --deploy-hook 'systemctl reload nginx'"
        # remove temporary nginx.conf and link config/server/nginx.conf to /etc/nginx/conf.d
        execute :su_rm, "/etc/nginx/conf.d/#{fetch(:application)}.conf"
        execute :su_ln, "-s -f #{server_conf_dir}/nginx.conf /etc/nginx/conf.d/#{fetch(:application)}.conf"
        execute :systemctl, :restart, :nginx
      end
    end
  end
end

desc 'Remove the application completely from the server'
task :remove do
  on roles(:all) do
    with fetch(:environment) do
      # stop, disable and remove systemd service files
      execute :systemctl, :stop, fetch(:application)
      execute :systemctl, :stop, "#{fetch(:application)}_sidekiq"
      execute :systemctl, :disable, fetch(:application)
      execute :systemctl, :disable, "#{fetch(:application)}_sidekiq"
      execute :su_rm, "-f /lib/systemd/system/#{fetch(:application)}.service"
      execute :su_rm, "-f /lib/systemd/system/#{fetch(:application)}_sidekiq.service"
      # dropt the database and remove the application directory from /home/deploy/apps
      within fetch(:deploy_to) do
        execute :rake, 'db:drop'
        execute :su_rm, "-rf #{fetch(:deploy_to)}"
      end if test "[ -d #{fetch(:deploy_to)} ]"
      # remove application nginx configuration
      execute :su_rm, "-f /etc/nginx/conf.d/#{fetch(:application)}.conf"
      execute :systemctl, :restart, :nginx
      # remove logrotate configuration
      execute :su_rm, "-f /etc/logrotate.d/#{fetch(:application)}"
    end
  end
end

desc 'Deploy rails application'
task :deploy do
  on roles(:all) do
    with fetch(:environment) do
      within fetch(:deploy_to) do
        invoke :fetch_and_reset_git_repository
        execute :bundle, :install
        execute :rake, 'db:migrate'
        execute :rake, 'assets:precompile'
        execute :systemctl, :restart, fetch(:application)
        execute :systemctl, :restart, "#{fetch(:application)}_sidekiq"
        execute :systemctl, :restart, :nginx
      end
    end
  end
end

desc 'Copy database from the server to the local machine and sync directories from the server'
task :update do
  on roles(:all) do
    within fetch(:deploy_to) do
      execute :pg_dump, "-U rails -h localhost --clean --no-owner #{fetch(:application)}_production > db/#{fetch(:application)}.sql"
      download! "#{fetch(:deploy_to)}/db/#{fetch(:application)}.sql", 'db'
    end
  end
  run_locally do
    execute "psql -d #{fetch(:application)}_development -f db/#{fetch(:application)}.sql"
  end
  invoke :sync_local_dirs_from_server
end

task :sync_local_dirs_from_server do
  on roles(:all) do
    fetch(:sync_dirs, []).each do |sync_dir|
      #if test "[ -f #{fetch(:deploy_to)}//#{sync_dir} ]"
        run_locally do
          execute "rsync -avzm --delete --force -e ssh #{fetch(:user)}@#{fetch(:server)}:#{fetch(:deploy_to)}/#{sync_dir}/ ./#{sync_dir}/"
        end
      #end
    end
  end
end

task :fetch_and_reset_git_repository do
  on roles(:all) do
    with fetch(:environment) do
      within fetch(:deploy_to) do
        execute :git, :fetch, 'origin'
        execute :git, :reset, "--hard origin/#{fetch(:deploy_branch, 'master')}"
      end
    end
  end
end

task :create_database_from_sql_file do
  on roles(:all) do
    with fetch(:environment) do
      within fetch(:deploy_to) do
        execute :rake, 'db:create'
        execute :rake, 'db:migrate'
        execute :rake, 'db:seed'
        if test "[ -f #{fetch(:deploy_to)}/db/#{fetch(:application)}.sql ]"
          execute :psql, "-U rails -h localhost -d #{fetch(:application)}_production", "-f db/#{fetch(:application)}.sql"
          execute :rake, 'db:migrate'
        end
      end
    end
  end
end