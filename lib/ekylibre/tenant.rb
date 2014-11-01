require 'apartment'
require 'ekylibre/schema'

module Ekylibre

  class TenantError < StandardError
  end

  class Tenant

    AGGREGATION_NAME = "__all__"

    class << self

      # Tests existence of a tenant
      def exist?(name)
        list.include?(name)
      end


      # Tests existence of a tenant in DB
      # and removes it if not exist
      def check!(name)
        if list.include?(name)
          unless Apartment.connection.schema_exists? name
            drop(name)
          end
        end
      end

      # Returns the current tenant
      def current
        unless name = Apartment::Tenant.current
          raise TenantError, "No current tenant"
        end
        return name
      end

      # Returns the private directory of the current tenant
      # If tenant name given, it returns its private_directory
      def private_directory(name = nil)
        Ekylibre.root.join("private", name || current)
      end

      # Create a new tenant
      def create(name)
        name = name.to_s
        check!(name)
        if exist?(name)
          raise TenantError, "Already existing tenant"
        end
        Apartment::Tenant.create(name)
        @list[env] ||= []
        @list[env] << name
        write
      end

      # Drop tenant
      def drop(name)
        name = name.to_s
        unless exist?(name)
          raise TenantError, "Unexistent tenant: #{name}"
        end
        if Apartment.connection.schema_exists? name
          Apartment::Tenant.drop(name)
        end
        FileUtils.rm_rf private_directory(name)
        @list[env].delete(name)
        write
      end

      # Migrate tenant to wanted version
      def migrate(name, options = {})
        if options[:to] ||= options[:up_to]
          Apartment::Migrator.run(:up, name, options[:to])
        elsif options[:down_to]
          Apartment::Migrator.run(:down, name, options[:down_to])
        else
          Apartment::Migrator.migrate(name)
        end
      end


      def rename(old, new)
        check!(old)
        unless exist?(old)
          raise TenantError, "Unexistent tenant: #{name}"
        end
        ActiveRecord::Base.connection.execute("ALTER SCHEMA #{old.to_s.inspect} RENAME TO #{new.to_s.inspect};")
        @list[env].delete(old.to_s)
        @list[env] << new.to_s
      end

      # Change current tenant
      def switch(name, &block)
        Apartment::Tenant.switch(name, &block)
      end
      alias :current= :switch

      def switch_default!(&block)
        if list.empty?
          raise TenantError, "No default tenant"
        else
          Apartment::Tenant.switch(list.first, &block)
        end
      end

      def clear!
        list unless @list
        @list[env] = []
        write
      end

      def list
        unless @list
          @list = (File.exist?(config_file) ? YAML.load_file(config_file) : {})
          @list ||= {}
          @list[env] ||= []
        end
        return @list[env]
      end

      def drop_aggregation_schema!
        ActiveRecord::Base.connection.execute("CREATE SCHEMA IF NOT EXISTS #{AGGREGATION_NAME};")
      end

      def create_aggregation_schema!
        create_aggregation_views_schema!
      end

      def create_aggregation_views_schema!
        if list.empty?
          raise "No tenant to build an aggregation schema"
        end
        name = AGGREGATION_NAME
        connection = ActiveRecord::Base.connection
        connection.execute("CREATE SCHEMA IF NOT EXISTS #{name};")
        for table in Ekylibre::Schema.tables.keys
          connection.execute "DROP VIEW IF EXISTS #{name}.#{table}"
          columns = Ekylibre::Schema.columns(table)
          queries = list.collect do |tenant|
            "SELECT '#{tenant}' AS tenant_name, " + columns.collect{|c| c[:name] }.join(", ") + " FROM #{tenant}.#{table}"
          end
          query = "CREATE VIEW #{name}.#{table} AS " + queries.join(" UNION ALL ")
          connection.execute(query)
        end
      end

      def reset_search_path!
        ActiveRecord::Base.connection.schema_search_path = Ekylibre::Application.config.database_configuration[::Rails.env]["schema_search_path"]
      end

      private

      def config_file
        Rails.root.join("config", "tenants.yml")
      end

      # Return the env
      def env
        Rails.env.to_s
      end

      def write
        FileUtils.mkdir_p(config_file.dirname)
        File.write(config_file, @list.to_yaml)
      end

    end

  end

end
