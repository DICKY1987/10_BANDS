@{
  Queue = @{
    RecoveryProcessingStaleMinutes = 10
    HeartbeatEverySeconds          = 5
    LogRotateMaxMB                 = 32
    LogKeepDays                    = 14
  }

  Retry = @{
    DefaultMaxRetries   = 3
    BackoffStartSeconds = 5
    BackoffMaxSeconds   = 120
    JitterSeconds       = 3
    RetryOnExitCodes    = @(1..255) # retry on any non-zero by default
  }

  CircuitBreaker = @{
    WindowFailures     = 5      # open after 5 consecutive failures
    OpenSeconds        = 600    # 10 minutes
  }

  Git = @{
    IndexLockStaleMinutes = 5
    AutoGC                = $true
    GcEveryMinutes        = 60
  }
}
