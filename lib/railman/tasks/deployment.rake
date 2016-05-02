set :deploy_to, "/home/deploy/apps/#{fetch(:application)}"
set :rbenv_home, '/home/deploy/.rbenv'
set :environment, {path: "#{fetch(:rbenv_home)}/shims:#{fetch(:rbenv_home)}/bin:$PATH", rails_env: 'production'}

SSHKit.config.command_map[:rake] = "#{fetch(:deploy_to)}/bin/rake"
%w(ln service start restart stop status).each do |cmd|
  SSHKit.config.command_map[cmd.to_sym] = "sudo #{cmd}"
end
SSHKit.config.command_map[:eye] = "#{fetch(:rbenv_home)}/shims/eye"
SSHKit.config.command_map[:su_rm] = "sudo rm"

desc "Setup rails application for the first time on a server"
task :setup do
  on roles(:all) do
    with fetch(:environment) do
      if test "[ -d #{fetch(:deploy_to)} ]"
        within fetch(:deploy_to) do
          execute :git, :fetch, 'origin'
          execute :git, :reset, '--hard origin/master'
        end
      else
        execute :git, :clone, fetch(:repo_url), fetch(:deploy_to)
      end
      server_conf_dir = "#{fetch(:deploy_to)}/config/server"
      execute :ln, "-s -f #{server_conf_dir}/nginx.conf /etc/nginx/conf.d/#{fetch(:application)}.conf"
      execute :ln, "-s -f #{server_conf_dir}/letsencrypt.conf /etc/nginx/letsencrypt/#{fetch(:application)}.conf"
      execute :ln, "-s -f #{server_conf_dir}/logrotate.conf /etc/logrotate.d/#{fetch(:application)}"
      within fetch(:deploy_to) do
        execute :bundle, :install, "--without development test"
        execute :mkdir, "-p #{fetch(:deploy_to)}/tmp/pids"
        if test "[ -f #{fetch(:deploy_to)}/.env ]"
          execute :rake, 'db:create'
          if test "[ -f #{fetch(:deploy_to)}/db/#{fetch(:application)}.sql ]"
            execute :psql, "-d #{fetch(:application)}_production", "-f db/#{fetch(:application)}.sql"
          end
          execute :rake, 'db:migrate'
          execute :rake, 'assets:precompile'
          execute :eye, :load, 'Eyefile'
          execute :eye, :start, fetch(:application)
          execute :service, "nginx restart"
        else
          warn "TODO: Create .env on the server by copying from .env.example.production and modify your database and smtp settings."
          warn "TODO: Create rails secret token with 'rake secret' and insert it into .env"
          warn "TODO: Create ssl certificates by running the following command as root: /etc/letsencrypt/generate_letsencrypt.sh"
          warn "TODO: Run 'cap ENV setup' again!"
        end
      end
    end
  end
end

desc "Remove the application completely from the server"
task :remove do
  on roles(:all) do
    with fetch(:environment) do
      within fetch(:deploy_to) do
        execute :eye, :load, 'Eyefile'
        execute :eye, :stop, fetch(:application)
        execute :rake, 'db:drop'
        execute :su_rm, "-rf #{fetch(:deploy_to)}"
      end if test "[ -d #{fetch(:deploy_to)} ]"
      execute :su_rm, "-f /etc/nginx/conf.d/#{fetch(:application)}.conf"
      execute :su_rm, "-f /etc/nginx/letsencrypt/#{fetch(:application)}.conf"
      execute :su_rm, "-f /etc/logrotate.d/#{fetch(:application)}"
      execute :service, "nginx restart"
    end
  end
end

desc "Deploy rails application"
task :deploy do
  on roles(:all) do
    with fetch(:environment) do
      within fetch(:deploy_to) do
        execute :git, :fetch, 'origin'
        execute :git, :reset, '--hard origin/master'
        execute :bundle, :install
        execute :rake, 'db:migrate'
        execute :rake, 'assets:precompile'
        execute :eye, :load, 'Eyefile'
        execute :eye, :restart, fetch(:application)
        execute :service, "nginx restart"
      end
    end
  end
end

desc "Copy database from the server to the local machine"
task :sync_local do
  on roles(:all) do
    within fetch(:deploy_to) do
      execute :pg_dump, "-U deploy --clean #{fetch(:application)}_production > db/#{fetch(:application)}.sql"
      download! "#{fetch(:deploy_to)}/db/#{fetch(:application)}.sql", 'db'
    end
  end
  run_locally do
    execute "psql -d #{fetch(:application)}_development -f db/#{fetch(:application)}.sql"
  end
end

desc "Recreate server database from db/#{fetch(:application)}.sql"
task :reset_server do
  on roles(:all) do
    with fetch(:environment) do
      within fetch(:deploy_to) do
        execute :eye, :load, 'Eyefile'
        execute :eye, :stop, fetch(:application)
        execute :git, :fetch, 'origin'
        execute :git, :reset, '--hard origin/master'
        execute :rake, 'db:drop'
        execute :rake, 'db:create'
        if test "[ -f #{fetch(:deploy_to)}/db/#{fetch(:application)}.sql ]"
          execute :psql, "-d #{fetch(:application)}_production", "-f db/#{fetch(:application)}.sql"
        end
        execute :rake, 'db:migrate'
        execute :eye, :start, fetch(:application)
        execute :service, "nginx restart"
      end
    end
  end
end
