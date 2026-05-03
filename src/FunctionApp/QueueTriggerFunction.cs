using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace FunctionApp;

/// <summary>
/// Processes messages from the Azure Queue Storage "work-items" queue.
/// Authentication to the storage account is handled exclusively via managed identity —
/// no connection strings or storage account keys are used.
///
/// The "WorkItemsStorage" connection prefix is resolved to a service URI via the
/// environment variable WorkItemsStorage__serviceUri (set in app settings / Bicep).
/// Azure SDK DefaultAzureCredential picks up the user-assigned managed identity
/// automatically when AZURE_CLIENT_ID is set.
/// </summary>
public class WorkItemProcessor
{
    private readonly ILogger<WorkItemProcessor> _logger;

    public WorkItemProcessor(ILogger<WorkItemProcessor> logger)
    {
        _logger = logger;
    }

    [Function(nameof(WorkItemProcessor))]
    public void Run(
        [QueueTrigger("work-items", Connection = "WorkItemsStorage")] string message,
        FunctionContext context)
    {
        _logger.LogInformation(
            "Processing work item. MessageId={MessageId} Body={Body}",
            context.InvocationId,
            message);

        // TODO: add your business logic here.
        // For example: deserialize a JSON payload, call downstream services, etc.

        _logger.LogInformation("Work item processed successfully.");
    }
}
