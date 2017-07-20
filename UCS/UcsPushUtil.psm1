$Script:Port = 80
$Script:UseSSL = $false

Function Invoke-UcsPushWebRequest 
{
  <#
      .SYNOPSIS
      Base-level function for all other API calls.

      .PARAMETER Quiet
      Silences warning messages and lets the caller handle messaging to the user.

      .DESCRIPTION
      A wrapper for Invoke-WebRequest which includes URL building to reduce code re-use. Resolves any encountered error codes to a human-readable description and presents a warning.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER ApiEndpoint
      The API endpoint in a format such as "mgmt/config/set"

      .PARAMETER Body
      Data to send to the phone.

      .PARAMETER Method
      Which method (get or post) to use with this request.

      .PARAMETER Timeout
      If an override of the default timeout is desired, it can be set here.

      .PARAMETER Retries
      Number of retries, including the first attempt - "1" represents retry off.

      .PARAMETER ContentType
      Defaults to "text/xml". Can be changed to specify another format. Some endpoints may use "application/json."
  #>
  #[ValidatePattern("^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$")]
  Param(
    [Parameter(Mandatory,HelpMessage = 'Add help message for user')][String]$IPv4Address,
    [Parameter(Mandatory,HelpMessage = 'Add help message for user')][String]$ApiEndpoint,
    [ValidateSet('Get','Post')][String]$Method = 'Post',
    [String]$Body,
    [String]$ContentType = 'text/xml',
    [Timespan]$Timeout = $Script:DefaultTimeout,
    [System.Management.Automation.Credential()][pscredential]$Credential = $Script:PushCredential,
    [int][ValidateRange(1,100)]$Retries = $Script:DefaultRetries
  )

  $ThisTimeout = $Timeout

  if($Script:UseSSL -eq $true) 
  {
    <#
        HTTPS requires some extra work.
        Polycom signs each of their devices with a certificate signed by their CA,
        and the certificate is assigned to the MAC address of the phone. However,
        the phones don't register themselves in DNS with that MAC address. As a
        result, we must overwrite the HOSTS file so the system will trust the certificate.
    #>
    Write-Debug -Message 'Using HTTPS codepath.'
    $Protocol = 'https'
    Try 
    {
      $ThisHost = Get-UcsPushHostname -IPv4Address $IPv4Address
      Write-Debug -Message (('Got hostname {0}.' -f $ThisHost))
      if(Test-UcsPushIsAdministrator -eq $true) 
      {
        Add-UcsPushHost -IPv4Address $IPv4Address -Hostname $ThisHost #We'll only set this if we get a hostname.
      } else 
      {
        Write-Warning -Message 'Not running with administrator rights. HTTPS may fail.'
      }
    }
    Catch 
    {
        Write-Error -Message ("Couldn't get hostname for {0}. {1}" -f $IPv4Address, $_)
        $ThisHost = $IPv4Address
    }
  }
  else 
  {
    $Protocol = 'http'
    $ThisHost = $IPv4Address
  }

  $ArgumentString = ''
  $ThisUri = ('{0}://{1}:{2}/{3}' -f $Protocol, $ThisHost, $Script:Port, $ApiEndpoint, $ArgumentString)
  #The retry system works by try/catching the command multiple times
  $RetriesRemaining = $Retries

  While($RetriesRemaining -gt 0) 
  {
    Try 
    {
      $ThisUri = New-Object -TypeName System.Uri -ArgumentList ($ThisUri)

      if($Body.Length -gt 0) 
      {
        Write-Debug -Message ("Invoking webrequest for `"{0}`" and sending {1}." -f $ThisUri, $Body)
        $RestOutput = Invoke-WebRequest -Uri $ThisUri -Credential $Credential -Body $Body -ContentType $ContentType -TimeoutSec $ThisTimeout.TotalSeconds -Method $Method -ErrorAction Stop
      }
      else 
      {
        Write-Debug -Message ("Invoking webrequest for `"{0}`", no body to send." -f $ThisUri)
        $RestOutput = Invoke-WebRequest -Uri $ThisUri -Credential $Credential -ContentType $ContentType -TimeoutSec $ThisTimeout.TotalSeconds -Method $Method -ErrorAction Stop
      }
      Break
    }
    Catch 
    {
      $RetriesRemaining-- #Deincrement the counter so we remember our state.

      if($RetriesRemaining -le 0) 
      {
          #Cleanup for SSL.
        if($Script:UseSSL -eq $true) 
        {
          if(Test-UcsPushIsAdministrator -eq $true) 
          {
            Remove-UcsPushHost -Hostname $ThisHost
          }
        }
  
        Write-Debug -Message ('Returned error was "{0}".' -f $_)
        Write-Error -Message "Couldn't connect to $ThisIpv4address." -ErrorAction Stop
      } else 
      {
        Write-Debug -Message ("Couldn't connect to IP {0} with error message `"{1}`" {2} retries remaining." -f $IPv4Address, $_, $RetriesRemaining)
      }
    }
  }

  #Cleanup for SSL.
  if($Script:UseSSL -eq $true) 
  {
    if(Test-UcsPushIsAdministrator -eq $true) 
    {
      Remove-UcsPushHost -Hostname $ThisHost
    }
  }

  if($RestOutput.Content -notlike "Push Message will be displayed successfully")
  {
    $Content = $Restoutput.Content
    Write-Error "Data successfully sent to $ThisIpv4address but may not be displayed. Error was '$Content.'"
  }

  Return $RestOutput
}
