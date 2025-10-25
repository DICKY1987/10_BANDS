# AutomationSuite/Config/CliToolsConfig.psd1
# Configuration for CLI tools to be executed and monitored

@{
    # Define the tools to run
    Tools = @(
        @{
            Name = "PingGoogle" # Unique identifier for the tool
            Path = "ping.exe"
            Arguments = @("google.com", "-t") # Example: Continuous ping
            Color = "Green" # ConsoleColor for output
        }
        @{
            Name = "PingLocal"
            Path = "ping.exe"
            Arguments = @("127.0.0.1", "-t")
            Color = "Cyan"
        }
        @{
            Name = "TimeoutTest"
            Path = "timeout.exe"
            Arguments = @("/t", "5", "/nobreak") # Example: waits for 5 seconds, repeats
            Color = "Yellow"
        }
        @{
            Name = "DirCmd"
            Path = "cmd.exe"
            Arguments = @("/c", "dir C:\ /s") # Example: Long directory listing
            Color = "Magenta"
        }
        # Add more tools here
    )

    # Monitor refresh rate in milliseconds
    MonitorRefreshRateMs = 200

    # Default color if tool color is not specified or invalid
    DefaultOutputColor = "Gray"
}

