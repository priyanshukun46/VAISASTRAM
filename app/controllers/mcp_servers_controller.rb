class McpServersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_server, only: [:show, :edit, :update, :destroy, :connect, :disconnect, :discover_tools, :toggle_enabled]
  before_action :authorize_server_access!, only: [:show, :edit, :update, :destroy, :connect, :disconnect, :discover_tools, :toggle_enabled]

  def index
    @servers = accessible_servers.order(created_at: :desc)
    @connected_count = @servers.where(status: "connected").count
    @total_tools_count = McpTool.where(mcp_server_id: @servers.select(:id)).count
    @enabled_tools_count = McpTool.where(mcp_server_id: @servers.select(:id), enabled: true).count

    # Marketplace templates (Ready to register)
    @templates = marketplace_templates
  end

  def new
    template_key = params[:template]
    template = marketplace_templates.find { |t| t[:key] == template_key }

    @server = current_user.present? ? current_user.mcp_servers.new : McpServer.new
    if template.present?
      @server.name = template[:name]
      @server.description = template[:description]
      @server.transport_type = template[:transport_type]
      @server.command = template[:command]
      @server.arguments = template[:arguments]
      @server.endpoint_url = template[:endpoint_url]
      @server.allow_local_connections = template[:allow_local_connections] || false
    else
      @server.transport_type = "stdio"
    end
  end

  def create
    @server = accessible_scope.new(mcp_server_params)
    @server.user = current_user

    if @server.save
      Audit::Recorder.record!(
        event_type: "mcp_server_created",
        actor_type: "user",
        actor_id: current_user.id.to_s,
        user: current_user,
        security_critical: false,
        metadata: {
          server_id: @server.id,
          server_name: @server.name,
          transport_type: @server.transport_type,
          server_identifier: @server.server_identifier
        }
      )

      # Automatically attempt initial connection and discovery if requested or enabled
      if params[:auto_connect] == "1" || @server.enabled?
        health = Mcp::Client.connect(@server)
        if health[:success]
          Mcp::Client.discover_tools(@server) rescue nil
          redirect_to mcp_server_path(@server), notice: "MCP Server '#{@server.name}' registered and connected successfully."
          return
        else
          redirect_to mcp_server_path(@server), alert: "MCP Server registered, but initial connection failed: #{health[:error]}"
          return
        end
      end

      redirect_to mcp_server_path(@server), notice: "MCP Server '#{@server.name}' created successfully."
    else
      @templates = marketplace_templates
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @tools = @server.mcp_tools.order(:external_tool_name)
    @audit_events = AuditEvent.where("metadata ->> 'server_id' = ?", @server.id.to_s).recent.limit(20)
  end

  def edit
  end

  def update
    old_version = @server.configuration_version

    if @server.update(mcp_server_params)
      if @server.configuration_version > old_version
        Audit::Recorder.record!(
          event_type: "mcp_server_configuration_changed",
          actor_type: "user",
          actor_id: current_user.id.to_s,
          user: current_user,
          security_critical: true,
          metadata: {
            server_id: @server.id,
            server_name: @server.name,
            old_version: old_version,
            new_version: @server.configuration_version
          }
        )
      end

      redirect_to mcp_server_path(@server), notice: "MCP Server configuration updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    server_name = @server.name
    server_id = @server.id

    Mcp::Client.disconnect(@server) rescue nil
    @server.destroy

    Audit::Recorder.record!(
      event_type: "mcp_server_removed",
      actor_type: "user",
      actor_id: current_user.id.to_s,
      user: current_user,
      security_critical: true,
      metadata: {
        server_id: server_id,
        server_name: server_name
      }
    )

    redirect_to mcp_servers_path, notice: "MCP Server '#{server_name}' was removed."
  end

  def connect
    result = Mcp::Client.connect(@server)
    if result[:success]
      # Auto-discover tools upon successful connection if none discovered yet
      if @server.mcp_tools.none?
        Mcp::Client.discover_tools(@server) rescue nil
      end
      redirect_to mcp_server_path(@server), notice: "Connected to '#{@server.name}' in #{result[:duration_ms]}ms."
    else
      redirect_to mcp_server_path(@server), alert: "Connection failed: #{result[:error]}"
    end
  end

  def disconnect
    Mcp::Client.disconnect(@server)
    redirect_to mcp_server_path(@server), notice: "Disconnected from '#{@server.name}'."
  end

  def discover_tools
    unless @server.connected?
      health = Mcp::Client.connect(@server)
      unless health[:success]
        redirect_to mcp_server_path(@server), alert: "Cannot discover tools: connection failed (#{health[:error]})."
        return
      end
    end

    begin
      tools = Mcp::Client.discover_tools(@server)
      redirect_to mcp_server_path(@server), notice: "Discovered #{tools.size} #{'tool'.pluralize(tools.size)} from '#{@server.name}'. Tools remain disabled until explicitly authorized."
    rescue StandardError => e
      redirect_to mcp_server_path(@server), alert: "Tool discovery failed: #{e.message}"
    end
  end

  def toggle_enabled
    new_state = !@server.enabled?
    @server.update!(enabled: new_state)

    if new_state
      Mcp::Client.connect(@server) rescue nil
    else
      Mcp::Client.disconnect(@server) rescue nil
    end

    status_word = new_state ? "enabled" : "disabled"
    redirect_to mcp_server_path(@server), notice: "MCP Server '#{@server.name}' is now #{status_word}."
  end

  private

  def set_server
    @server = accessible_servers.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to mcp_servers_path, alert: "MCP Server not found or access denied."
  end

  def authorize_server_access!
    return if current_user.admin? || @server.user_id == current_user.id || @server.user_id.nil?

    redirect_to mcp_servers_path, alert: "You are not authorized to manage this MCP Server."
  end

  def accessible_scope
    current_user.admin? ? McpServer : current_user.mcp_servers
  end

  def accessible_servers
    if current_user.admin?
      McpServer.all
    else
      McpServer.where("user_id = ? OR user_id IS NULL", current_user.id)
    end
  end

  def mcp_server_params
    permitted = [
      :name, :server_identifier, :description, :transport_type,
      :command, :endpoint_url, :connection_timeout, :request_timeout,
      :enabled, :environment_variables, :authentication_configuration
    ]

    # Admin only options
    if current_user.admin?
      permitted << :allow_local_connections
    end

    params_hash = params.require(:mcp_server).permit(*permitted)

    # Process arguments if passed as a string or array
    if params[:mcp_server][:arguments_string].present?
      params_hash[:arguments] = Shellwords.split(params[:mcp_server][:arguments_string]) rescue params[:mcp_server][:arguments_string].split
    elsif params[:mcp_server][:arguments].present?
      params_hash[:arguments] = params[:mcp_server][:arguments]
    end

    params_hash
  end

  def marketplace_templates
    [
      {
        key: "redbus",
        name: "RedBus Fare & Ticket Inspector",
        description: "Official Model Context Protocol (MCP) server for intercity bus ticket prices, seat layout inspection, operator comparisons, and route fare estimation across Indian routes.",
        transport_type: "stdio",
        command: "ruby",
        arguments: ["bin/mcp-redbus-server"],
        allow_local_connections: false,
        icon: "truck",
        category: "Travel & Logistics",
        initial_tools: ["search_bus_routes", "get_ticket_price", "check_seat_layout", "estimate_route_fare"]
      },
      {
        key: "wordcraft",
        name: "WordCraft Document Engine",
        description: "Official MCP integration for WordCraft Markdown document manipulation, page rendering, and command inspection.",
        transport_type: "stdio",
        command: "npx",
        arguments: ["-y", "wordcraft", "mcp"],
        allow_local_connections: false,
        icon: "document",
        category: "Productivity",
        initial_tools: ["inspect_document", "list_commands", "render_page"]
      },
      {
        key: "weather",
        name: "Global Weather Service",
        description: "Standard Streamable HTTP MCP service providing live meteorological metrics and severe storm alerts.",
        transport_type: "streamable_http",
        endpoint_url: "https://api.weather-mcp.vaisastram.org/v1/mcp",
        allow_local_connections: false,
        icon: "cloud",
        category: "External APIs",
        initial_tools: ["get_forecast", "get_alerts"]
      },
      {
        key: "filesystem",
        name: "Governed File Inspector",
        description: "Local STDIO file inspector with read-only sandbox restrictions for workspace documents.",
        transport_type: "stdio",
        command: "npx",
        arguments: ["-y", "@modelcontextprotocol/server-filesystem", "./storage"],
        allow_local_connections: false,
        icon: "folder",
        category: "System Tools",
        initial_tools: ["read_file", "list_directory"]
      },
      {
        key: "postgres_inspector",
        name: "Database Schema Inspector",
        description: "Read-only database introspection tool to examine tables, indexes, and constraint metadata.",
        transport_type: "stdio",
        command: "npx",
        arguments: ["-y", "@modelcontextprotocol/server-postgres"],
        allow_local_connections: false,
        icon: "database",
        category: "Data & Storage",
        initial_tools: ["describe_table", "list_tables"]
      }
    ]
  end
end
