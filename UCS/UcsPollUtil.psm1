$Script:DefaultRetries = 3
$Script:DefaultTimeout = New-Timespan -Seconds 3
$Script:PollingCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ('UCSToolkit', (ConvertTo-SecureString -String 'UCSToolkit' -AsPlainText -Force))

Function Invoke-UcsPollRequest {
  Param(
    [Parameter(Mandatory,HelpMessage = 'Add help message for user')][String]$IPv4Address,
    [Parameter(Mandatory,HelpMessage = 'Add help message for user')][String]$ApiEndpoint,
    [ValidateSet('Get')][String]$Method = 'Get',
    [Timespan]$Timeout = $Script:DefaultTimeout,
    [System.Management.Automation.Credential()][pscredential]$Credential = $Script:PollingCredential,
    [int][ValidateRange(1,100)]$Retries = $Script:DefaultRetries
    )
    
    #TODO: Support for HTTPS
  
  $Protocol = "http"
  $ThisIPv4Address = $IPv4Address
  $ThisHost = $ThisIPv4Address
  $ThisPort = 80
  $ThisTimeout = $Timeout
  $ThisUri = ('{0}://{1}:{2}/{3}' -f $Protocol, $ThisHost, $ThisPort, $ApiEndpoint)
  #The retry system works by try/catching the command multiple times
  $RetriesRemaining = $Retries

  While($RetriesRemaining -gt 0) 
  {
    Try 
    {

      Write-Debug -Message ("Invoking webrequest for `"{0}`", no body to send." -f $ThisUri)
      $RestOutput = Invoke-WebRequest -Uri $ThisUri -TimeoutSec $ThisTimeout.TotalSeconds -Method $Method -Credential $Credential -ErrorAction Stop
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
        $AuthenticationError = $true
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
  $Content = $Content.FirstChild
  
  Return $Content
}