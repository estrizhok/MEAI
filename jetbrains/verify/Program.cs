using System;
using System.Text.Json;
using Microsoft.Extensions.AI;

var jsonAssembly = typeof(JsonSerializer).Assembly;
Console.WriteLine($"System.Text.Json {jsonAssembly.GetName().Version} from {jsonAssembly.Location}");
if (jsonAssembly.GetName().Version?.Major != 8)
{
    throw new InvalidOperationException("The smoke test must run with System.Text.Json 8.x.");
}

var function = AIFunctionFactory.Create((string name) => $"hello {name}");
Console.WriteLine(function.JsonSchema);
