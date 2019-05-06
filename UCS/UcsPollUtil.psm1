Function Invoke-UcsPollRequest {
  Param(
    [Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String]$IPv4Address,
    [Parameter(Mandatory,HelpMessage = 'polling/example')][String]$ApiEndpoint,
    [ValidateSet('Get')][String]$Method = 'Get',
    [Timespan]$Timeout = (Get-UcsConfig -API Poll).Timeout,
    [PsCredential[]]$Credential = (Get-UcsConfigCredential -API Poll -CredentialOnly),
    [int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -API Poll).Retries,
    [int][ValidateRange(1,65535)]$Port = (Get-UcsConfig -API Poll).Port,
    [Nullable[boolean]]$UseHTTPS = (Get-UcsConfig -API Poll).EnableEncryption
    )

    #TODO: Support for HTTPS

  $Protocol = "http"
  $ThisIPv4Address = $IPv4Address
  $ThisHost = $ThisIPv4Address
  $ThisUri = ('{0}://{1}:{2}/{3}' -f $Protocol, $ThisHost, $Port, $ApiEndpoint)
  #The retry system works by try/catching the command multiple times
  $RetriesRemaining = $Retries

  While($RetriesRemaining -gt 0)
  {
    Try
    {
      $ThisCredential = $Credential[0] #TODO: We don't yet support credential arrays, so for now, we get the first one.
      Write-Debug -Message ("Invoking webrequest for `"{0}`", no body to send." -f $ThisUri)
      $RestOutput = Invoke-WebRequest -Uri $ThisUri -TimeoutSec $Timeout.TotalSeconds -Method $Method -Credential $ThisCredential -ErrorAction Stop
      Break #We only break if the previous thing didn't fail.
    }
    Catch
    {
      $RetriesRemaining-- #Deincrement the counter so we remember our state.
      $ErrorStatusCode = $_.Exception.Response.StatusCode.Value__ #Returns null if it timed out.

      if($ErrorStatusCode -eq '403')
      {
        #No number of retries will fix an authentication error.
        Write-Debug "403 error returned - wrong credentials. Skipping retries."
        $RetriesRemaining = 0
      }
      elseif($ErrorStatusCode -eq '404')
      {
        Write-Debug "404 error returned - API is disabled on phone. Skipping retries."
        $RetriesRemaining = 0
      }

      if($RetriesRemaining -le 0)
      {
        Write-Debug -Message ('Returned error was "{0}".' -f $_)
        Write-Error -Message ("Couldn't connect to IP {0}." -f $IPv4Address)
      } else
      {
        Write-Debug -Message ("Couldn't connect to IP {0} with error message `"{1}`" {2} retries remaining." -f $IPv4Address, $_, $RetriesRemaining)
      }
    }
  }

  $Content = [XML]$RestOutput.Content
  $Content = $Content.PolycomIPPhone
  $ContentMainProperty = $Content | Get-Member -MemberType Property | Select-Object -ExpandProperty Name
  $Content = $Content.$ContentMainProperty

  Return $Content
}