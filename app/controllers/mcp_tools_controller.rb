class McpToolsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_server_and_tool

  def toggle
    new_state = !@tool.enabled?
    @tool.update!(enabled: new_state)

    event_type = new_state ? "mcp_tool_enabled" : "mcp_tool_disabled"
    Audit::Recorder.record!(
      event_type: event_type,
      actor_type: "user",
      actor_id: current_user.id.to_s,
      user: current_user,
      tool_name: @tool.namespaced_tool_key,
      security_critical: true,
      metadata: {
        server_id: @server.id,
        server_name: @server.name,
        tool_name: @tool.external_tool_name,
        namespaced_tool_key: @tool.namespaced_tool_key,
        enabled: new_state,
        policy_decision: @tool.policy_decision
      }
    )

    notice_msg = "Tool '#{@tool.external_tool_name}' is now #{new_state ? 'ENABLED' : 'DISABLED'}."
    redirect_to mcp_server_path(@server), notice: notice_msg
  end

  def update
    permitted = params.require(:mcp_tool).permit(:policy_decision, :risk_classification, :enabled)

    if @tool.update(permitted)
      Audit::Recorder.record!(
        event_type: "policy_modified",
        actor_type: "user",
        actor_id: current_user.id.to_s,
        user: current_user,
        tool_name: @tool.namespaced_tool_key,
        security_critical: true,
        metadata: {
          server_id: @server.id,
          tool_name: @tool.external_tool_name,
          policy_decision: @tool.policy_decision,
          risk_classification: @tool.risk_classification,
          enabled: @tool.enabled?
        }
      )

      redirect_to mcp_server_path(@server), notice: "Policy for '#{@tool.external_tool_name}' updated successfully."
    else
      redirect_to mcp_server_path(@server), alert: "Failed to update tool: #{@tool.errors.full_messages.join(', ')}"
    end
  end

  private

  def set_server_and_tool
    @server = if current_user.admin?
      McpServer.find(params[:mcp_server_id])
    else
      McpServer.where("user_id = ? OR user_id IS NULL", current_user.id).find(params[:mcp_server_id])
    end

    @tool = @server.mcp_tools.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to mcp_servers_path, alert: "MCP Server or Tool not found."
  end
end
