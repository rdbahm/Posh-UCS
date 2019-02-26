Function Invoke-UcsWebRequest 
{
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String]$IPv4Address,
    [Parameter(Mandatory,HelpMessage = 'api/test/example')][String]$ApiEndpoint,
    [ValidateSet('Get','Post','Put')][String]$Method = 'Get',
    $Body = $null,
    [String]$ContentType,
    [Timespan]$Timeout = (Get-UcsConfig -API Web).Timeout,
    [PsCredential[]]$Credential = (Get-UcsConfigCredential -API Web -CredentialOnly),
    [int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -API Web).Retries,
    [int][ValidateRange(1,65535)]$Port = (Get-UcsConfig -API Web).Port,
    [Nullable[boolean]]$UseHTTPS = (Get-UcsConfig -API Web).EnableEncryption
  )

  $ThisIPv4Address = $IPv4Address
  
  $Protocol = "http" #SSL support has been removed from this invoke.
  $ThisHost = $ThisIPv4Address
  
  $ThisUri = ('{0}://{1}:{2}/{3}' -f $Protocol, $ThisHost, $Port, $ApiEndpoint)
  #The retry system works by try/catching the command multiple times
  $RetriesRemaining = $Retries
  $ThisCredentialIndex = 0

  While($RetriesRemaining -gt 0) 
  {
    #Credential handler.
    $ThisCredential = $Credential[$ThisCredentialIndex]
    
    $Username = $ThisCredential.UserName
    $Password = [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($ThisCredential.Password))
    
    $Session = New-Object -TypeName Microsoft.PowerShell.Commands.WebRequestSession
    $Cookie = New-UcsWebCookie -Username $Username -Password $Password -Hostname $ThisHost
    $Session.Cookies.Add($Cookie)
  
    #This section attempts to make the request look more real to the phone. As far as I can tell, the phone probably doesn't care.
    $BasicAuth = ('Basic {0}' -f ( Convert-UcsWebToBase64 -String ('{0}:{1}' -f $Username, $Password) ) )
    $Header = @{
      Authorization = $BasicAuth
      Accept        = '*/*'
      Referer       = ('{0}://{1}/index.htm' -f $Protocol, $ThisHost)
      Origin        = ('{0}://{1}' -f $Protocol, $ThisHost)
    }
    
    #Request loop.
    Try 
    {
      if($Body.Length -gt 0) 
      {
        Write-Debug -Message ("Invoking webrequest for `"{0}`" and sending {1}." -f $ThisUri, $Body)
        $RestOutput = Invoke-WebRequest -Uri $ThisUri -WebSession $Session -Headers $Header -Body $Body -ContentType $ContentType -TimeoutSec $Timeout.TotalSeconds -Method $Method -UseBasicParsing -ErrorAction Stop
      }
      else 
      {
        Write-Debug -Message ("Invoking webrequest for `"{0}`", no body to send." -f $ThisUri)
        $RestOutput = Invoke-WebRequest -Uri $ThisUri -WebSession $Session -Headers $Header -ContentType $ContentType -TimeoutSec $Timeout.TotalSeconds -Method $Method -UseBasicParsing -ErrorAction Stop
      }
      Break
    }
    Catch 
    {
      $RetriesRemaining-- #Deincrement the counter so we remember our state.
      $ErrorStatusCode = $_.Exception.Response.StatusCode.Value__ #Returns null if it timed out.
      $Category = "ConnectionError"
      
      if($ErrorStatusCode -eq '403' -or $ErrorStatusCode -eq '401')
      {
        #Authentication error.
        $Category = "AuthenticationError"
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

  Return $RestOutput.Content
}

Function Convert-UcsWebToBase64 
{
  <#
      .SYNOPSIS
      Encodes to Polycom's Base64 authentication string

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER String
      Describe parameter -String.

      .EXAMPLE
      Convert-UcsWebToBase64 -String Value
      Describe what this call does

      .NOTES
      Re-implemented for Powershell to allow authentication to the web UI.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Convert-UcsWebToBase64

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  Param([Parameter(Mandatory)][String]$String)
  $bytes = [System.Text.Encoding]::ASCII.GetBytes($String)
  $base64 = [System.Convert]::ToBase64String($bytes)
  return $base64
}

Function New-UcsWebCookie 
{
  <#
      .SYNOPSIS
      Describe purpose of "New-UcsWebCookie" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER Username
      Describe parameter -Username.

      .PARAMETER Password
      Describe parameter -Password.

      .PARAMETER Hostname
      Describe parameter -Hostname.

      .EXAMPLE
      New-UcsWebCookie -Username Value -Password Value -Hostname Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online New-UcsWebCookie

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  Param([Parameter(Mandatory)][String][ValidateSet('User','Polycom')]$Username,[Parameter(Mandatory)][String]$Password,[Parameter(Mandatory)][String]$Hostname)

  $AuthHeader = ('{0}:{1}' -f $Username, $Password)
  $Encoded = Convert-UcsWebToBase64 -String $AuthHeader

  $Cookie = New-Object -TypeName System.Net.Cookie 
    
  $Cookie.Name = 'Authorization'
  $Cookie.Value = ('Basic {0}' -f $Encoded)
  $Cookie.Domain = $Hostname
   
  Return $Cookie
}

Function Get-UcsWebHostname 
{
  <#
      .SYNOPSIS
      Makes a web request to a Polycom phone's HTTPS address by IP address. Reads the certificate and returns the certificate's hostname.

      .DESCRIPTION
      The hostname is the phone's MAC address - so this is one of the easier ways to get the MAC address, and it doesn't require credentials.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .EXAMPLE
      Get-UcsHostname -IPv4Address Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      Based on code from StackOverflow.
      http://stackoverflow.com/a/22236908

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>

  Param(
    [Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address
  )

  $URI = ('https://{0}' -f $IPv4Address)
  $Request = [Net.HttpWebRequest]::Create($URI)

  try
  {
    #Make the request but ignore (dispose it) the response, since we only care about the service point
    $Request.GetResponse().Dispose()
  }
  catch [Net.WebException]
  {
    if ($_.Exception.Status -ne [Net.WebExceptionStatus]::TrustFailure)
    {
      #We ignore trust failures, since we only want the certificate.
      #Let other exceptions bubble up, or write-error the exception and return from this method
      Write-Error $_ -ErrorAction Stop
    }
  }

  #The ServicePoint object should now contain the Certificate for the site.
  $servicePoint = $Request.ServicePoint
  $Subject = $servicePoint.Certificate.Subject #This now contains something like "CN=0004F28B54F4, O=Polycom Inc."
  $Matches = $null
  if($Subject -match '[0-9a-f]{12}')
  {
    Return $Matches[0]
  }
  else
  {
    Write-Error "Couldn't get a result for $IPv4Address."
    Return $null
  }
}
