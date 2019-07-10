Function Invoke-UcsRestMethod 
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
      Defaults to "application/json". Can be changed to specify another format. Some endpoints may use "text/xml."
  #>
  #[ValidatePattern("^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$")]
  Param(
    [Parameter(Mandatory,HelpMessage = '127.0.0.1')][String]$IPv4Address,
    [Parameter(Mandatory,HelpMessage = 'api/v1/example/string')][String]$ApiEndpoint,
    [ValidateSet('Get','Post')][String]$Method = 'Get',
    [String]$Body,
    [String]$ContentType = 'application/json',
    [Timespan]$Timeout = (Get-UcsConfig -API REST).Timeout,
    [PsCredential[]]$Credential = (Get-UcsConfigCredential -API REST -CredentialOnly),
    [int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -API REST).Retries,
    [int][ValidateRange(1,65535)]$Port = (Get-UcsConfig -API REST).Port,
    [boolean]$UseHTTPS = (Get-UcsConfig -API REST).EnableEncryption
  )

  if($UseHTTPS -eq $true) 
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
      if(Test-UcsIsAdministrator -eq $true) 
      {
        $ThisHost = Get-UcsHostname -IPv4Address $IPv4Address
        Write-Debug -Message (('Got hostname {0}.' -f $ThisHost))
        Add-UcsHost -IPv4Address $IPv4Address -Hostname $ThisHost #We'll only set this if we get a hostname.
      }
      else
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
    #Regular HTTP codepath.
    $Protocol = 'http'
    $ThisHost = $IPv4Address
  }

  $ArgumentString = ''
  $ThisUri = ('{0}://{1}:{2}/{3}' -f $Protocol, $ThisHost, $Port, $ApiEndpoint, $ArgumentString)
  
  #The retry system works by try/catching the command multiple times.
  $RetriesRemaining = $Retries
  $ThisCredentialIndex = 0

  While($RetriesRemaining -gt 0) 
  {
    $ThisCredential = $Credential[$ThisCredentialIndex]
    Try 
    {    
      if($Body.Length -gt 0) 
      {
        Write-Debug -Message ("Invoking RestMethod for `"{0}`" and sending {1}." -f $ThisUri, $Body)
        $RestOutput = Invoke-RestMethod -Uri $ThisUri -Credential $ThisCredential -Body $Body -ContentType $ContentType -TimeoutSec $Timeout.TotalSeconds -Method $Method -ErrorAction Stop
      }
      else 
      {
        Write-Debug -Message ("Invoking RestMethod for `"{0}`", no body to send." -f $ThisUri)
        $RestOutput = Invoke-RestMethod -Uri $ThisUri -Credential $ThisCredential -ContentType $ContentType -TimeoutSec $Timeout.TotalSeconds -Method $Method -ErrorAction Stop
      }
      Break #If we got here, there was no error, so we break from the loop.
    }
    Catch 
    {
      $RetriesRemaining-- #Deincrement the counter so we remember our state.
      $ErrorStatusCode = $_.Exception.Response.StatusCode.Value__ #Returns null if it timed out.

            if($ErrorStatusCode -eq '403' -or $ErrorStatusCode -eq '401')
            {
              #No number of retries will fix an authentication error.
             
              $Exception = New-Object System.UnauthorizedAccessException ("Couldn't connect. REST API may be disabled on $IPv4Address.",$_.Exception)
              $ThisCredentialIndex++
              
              if($ThisCredentialIndex -lt $Credential.Count)
              {
                $RetriesRemaining++ #Restore this failure so we can try with our new credential.
                Write-Debug "Trying new credentials..."
              }
              else
              {
                $RetriesRemaining = 0 #No credentials left and it's not worth trying.
              }
            }
            elseif($ErrorStatusCode -eq '404')
            {
              $Exception = New-Object System.Runtime.InteropServices.ExternalException ("Couldn't connect. REST API may be disabled on $IPv4Address.",$_.Exception)
              $RetriesRemaining = 0
            }
            else
            {
              $Exception = New-Object System.Runtime.InteropServices.ExternalException ("An error occurred while connecting to $IPv4Address.",$_.Exception)
            }
            
      if($RetriesRemaining -le 0) 
      {
        #Cleanup for SSL. Copypasta'd from below to avoid issues where we litter the hosts file.
        if($UseHTTPS -eq $true) 
        {
          if(Test-UcsIsAdministrator -eq $true) 
          {
            Remove-UcsHost -Hostname $ThisHost
          }
        }
        
        Throw $Exception
      }
      else 
      {
        #Retries are remaining, so we'll be quiet until we actually fail...
        Write-Debug -Message ("Couldn't connect to IP {0} with error message `"{1}`" {2} retries remaining." -f $IPv4Address, $_, $RetriesRemaining)
      }
    }
  }

  #Cleanup for SSL.
  if($UseHTTPS -eq $true)
  {
    if(Test-UcsIsAdministrator -eq $true) 
    {
      Remove-UcsHost -Hostname $ThisHost
    }
  }

  if($RestOutput.Status) 
  {
    $ThisStatus = Get-UcsStatusCodeString -StatusCode ($RestOutput.Status) -IPv4Address $IPv4Address -ApiEndpoint $ApiEndpoint
    $RestOutput.Status = $ThisStatus
    if($ThisStatus.IsSuccess -eq $false) 
    {
      Throw $ThisStatus.Exception
    }
  }

  Return $RestOutput
}

Function Convert-UcsRestDuration 
{
  <#
      .SYNOPSIS
      Gets a call duration from output, then converts to a timespan.

      .DESCRIPTION
      Takes a pattern such as "5 mins 25 secs" and converts to a standard timespan.

      .PARAMETER Duration
      Duration string from UCS.

      .EXAMPLE
      Convert-UcsDuration -Duration Value
      Returns a timespan object.

      .OUTPUTS
      Timespan
  #>
  Param ([Parameter(Mandatory,HelpMessage = '1 day 2 hours 3 mins 1 sec')][String]$Duration)
  
  $AvailableStrings = ('day','hour','min','sec')

  #This is about the least programmer-friendly return for a REST API that I can imagine.
  #Format is "1 day 2 hours 3 mins 12 secs".
  #I've not found documentation on the generation of the string, so I've only confirmed...
  #that minutes and seconds work this way - unsure if hours or days are abbreviated.
  #I'm also not sure that they even give you hours and days.
  #But I can confirm that they unhelpfully pluralize the words when appropriate.
  
  Foreach($Interval in $AvailableStrings)
  {
    if ($Duration -match ('\d+ (?={0}s?)' -f $Interval))
    {
      $IntervalValue = [Int]$Matches[0]
      Write-Debug "Found a duration for $Interval. $ThisDuration"
      
    }
    else
    {
      $IntervalValue = 0
    }
    
    Set-Variable -Name $Interval -Value $IntervalValue
  }

  return New-TimeSpan -Days $day -Hours $hour -Minutes $min -Seconds $sec
}
