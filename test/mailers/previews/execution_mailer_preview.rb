class ExecutionMailerPreview < ActionMailer::Preview
  def execution_started
    execution = Execution.first || mock_execution
    ExecutionMailer.execution_started(execution)
  end

  def execution_completed
    execution = Execution.completed.first || mock_execution(status: "completed")
    ExecutionMailer.execution_completed(execution)
  end

  def execution_failed
    execution = Execution.failed.first || mock_execution(status: "failed", error: "Database connection timed out during step execution")
    ExecutionMailer.execution_failed(execution, error: "Database connection timed out during step execution")
  end

  private

  def mock_execution(status: "running", error: nil)
    user = User.first || User.new(name: "Operator Jane", email: "jane@vaisastram.internal")
    agent = Agent.first || Agent.new(name: "VAISASTRAM Agent")
    task = Task.first || Task.new(id: 77, user: user, title: "Reconcile vendor batch ledger")
    Execution.new(
      id: 501,
      task: task,
      agent: agent,
      status: status,
      provider: "gemini",
      ai_model: "gemini-2.5-pro",
      started_at: 10.minutes.ago,
      completed_at: Time.current,
      error_message: error
    )
  end
end
