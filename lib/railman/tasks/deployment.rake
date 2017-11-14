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
      execute :cp, "#{server_conf_dir}/nginx.conf /etc/nginx/sites-available/#{fetch(:domain)}"
      execute :ln, "-s -f /etc/nginx/sites-available/#{fetch(:domain)}.conf /etc/nginx/sites-enabled/"
      execute :ln, "-s -f #{server_conf_dir}/logrotate.conf /etc/logrotate.d/#{fetch(:application)}"
      within fetch(:deploy_to) do
        execute :bundle, :install, '--without development test'
        execute :mkdir, "-p #{fetch(:deploy_to)}/tmp/pids"
        if test "[ -f #{fetch(:deploy_to)}/.env ]"
          invoke :create_database_from_sql_file
          execute :rake, 'assets:precompile'
          execute :eye, :load, 'Eyefile'
          execute :eye, :start, fetch(:application)
          execute :service, 'nginx restart'
          execute :certbot, "--nginx -d #{fetch(:domain)}"
        else
          execute 'cp .env.example.production', '.env'
          execute "sed -i -e 's/TODO: generate with: rake secret/#{SecureRandom.hex(64)}/g' #{fetch(:deploy_to)}/.env"
          warn 'TODO: Edit .env and modify your database and smtp settings.'
          warn 'TODO: Run \'cap ENV setup\' again!'
        end
      end
    end
  end
end

desc 'Remove the application completely from the server'
task :remove do
  on roles(:all) do
    with fetch(:environment) do
      within fetch(:deploy_to) do
        execute :eye, :load, 'Eyefile'
        execute :eye, :stop, fetch(:application)
        execute :rake, 'db:drop'
        execute :su_rm, "-rf #{fetch(:deploy_to)}"
      end if test "[ -d #{fetch(:deploy_to)} ]"
      execute :su_rm, "-f /etc/nginx/sites-enabled/#{fetch(:domain)}"
      execute :su_rm, "-f /etc/nginx/sites-available/#{fetch(:domain)}"
      execute :su_rm, "-f /etc/logrotate.d/#{fetch(:application)}"
      execute :service, 'nginx restart'
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
        execute :eye, :load, 'Eyefile'
        execute :eye, :restart, fetch(:application)
        execute :service, 'nginx restart'
      end
    end
  end
end

desc 'Copy database from the server to the local machine'
task :update do
  on roles(:all) do
    within fetch(:deploy_to) do
      execute :pg_dump, "-U deploy --clean #{fetch(:application)}_production > db/#{fetch(:application)}.sql"
      download! "#{fetch(:deploy_to)}/db/#{fetch(:application)}.sql", 'db'
    end
  end
  run_locally do
    execute "psql -d #{fetch(:application)}_development -f db/#{fetch(:application)}.sql"
    invoke :sync_local_dirs_from_server
  end
end

desc "Recreate server database from db/#{fetch(:application)}.sql and sync local dirs if any"
task :reset_server do
  on roles(:all) do
    with fetch(:environment) do
      within fetch(:deploy_to) do
        execute :eye, :load, 'Eyefile'
        execute :eye, :stop, fetch(:application)
        sleep 6 # seconds
        invoke :fetch_and_reset_git_repository
        execute :rake, 'db:drop'
        invoke :create_database_from_sql_file
        invoke :sync_local_dirs_to_server
        execute :eye, :start, fetch(:application)
        execute :service, 'nginx restart'
      end
    end
  end
end

task :sync_local_dirs_to_server do
  on roles(:all) do
    fetch(:sync_dirs, []).each do |sync_dir|
      run_locally do
        execute "rsync -avz --delete -e ssh ./#{sync_dir}/ #{fetch(:user)}@#{fetch(:server)}:#{fetch(:deploy_to)}/#{sync_dir}/"
      end
    end
  end
end

task :sync_local_dirs_from_server do
  on roles(:all) do
    fetch(:sync_dirs, []).each do |sync_dir|
      run_locally do
        execute "rsync -avzm --delete --force -e ssh #{fetch(:user)}@#{fetch(:server)}:#{fetch(:deploy_to)}/#{sync_dir}/ ./#{sync_dir}/"
      end
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
        if test "[ -f #{fetch(:deploy_to)}/db/#{fetch(:application)}.sql ]"
          execute :psql, "-d #{fetch(:application)}_production", "-f db/#{fetch(:application)}.sql"
        end
        execute :rake, 'db:migrate'
      end
    end
  end
end