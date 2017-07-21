<#### API-Specific Configuration ####>
$Script:Port = 80
$Script:UseHTTPS = $false
$Script:DefaultTimeout = New-Timespan -Seconds 2
$Script:DefaultRetries = 3 

$Script:PushCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ('UCSToolkit', (ConvertTo-SecureString -String 'UCSToolkit' -AsPlainText -Force))


<#### FUNCTION DEFINITONS ####>

<## API Configuration ##>
Function Set-UcsPushAPIConnectionSetting
{
  Param([Int][ValidateRange(1,65535)]$Port = $null,
    [Bool]$UseHTTPS = $null,
    [Timespan]$Timeout = $null,
    [Int]$Retries = $null
  )
  
  if($Port -ne $null)
  {
    $Script:Port = $Port
  }
  if($UseHTTPS -ne $null)
  {
    $Script:UseHTTPS = $UseHTTPS
  }
  if($Timeout -ne $null)
  {
    $Script:DefaultTimeout = $Timeout
  }
  if($Retries -ne $null)
  {
    $Script:DefaultRetries = $Retries
  }
}

Function Get-UcsPushAPIConnectionSetting
{
  $OutputObject = 1 | Select-Object @{Name='Port';Expression={$Script:Port}},@{Name='UseHTTPS';Expression={$Script:UseHTTPS}},@{Name='Timeout';Expression={$Script:DefaultTimeout}},@{Name='Retries';Expression={$Script:DefaultRetries}}
  Return $OutputObject
}

Function Set-UcsPushAPICredential
{
  Param([Parameter(Mandatory)][PsCredential[]]$Credential)
  
  $Script:PushCredential = $Credential
}

Function Get-UcsPushAPICredential
{
  Return $Script:PushCredential
}


<## Phone cmdlets ##>
Function Start-UcsPushCall
{
  <#
      .SYNOPSIS
      Start a call on a VVX.

      .DESCRIPTION
      Sends a call to the phone via the Push API.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Priority
      Describe parameter -Priority.

      .PARAMETER PassThru
      Returns an object with call status for this phone. Uses Get-UcsCallStatus, so either REST or Poll APIs must be available.

      .EXAMPLE
      Send-CallAction -IPv4Address Value -Priority Value -CallAction Value
      Describe what this call does

      .NOTES
      Additional configuration is required to run this. The phone's "Push" credentials must be set (this script defaults to using "UCSToolkit" for both), "Allow Push Messages" must be set to "Critical" or lower, and "Application Server Root URL" must be specified. HTTPS must be enabled using Set-UcsPushConnectionSettings. Additionally, in Skype for Business deployments, the script must be run from a pool server.
  #>
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String]$IPv4Address,
    [ValidateSet('Critical','Important','High','Normal')][String]$Priority = 'Critical',
    [Parameter(Mandatory,HelpMessage = 'Add help message for user')][String]$Destination,
    [Int][ValidateRange(1,24)]$LineId = 1,
    [Switch]$PassThru)
  
  Begin
  {
    $OutputArray = New-Object Collections.Arraylist
  }
  Process
  {
  $ThisIPv4Address = $IPv4Address
  
  #Calls to numbers need to be prefixed with \\, all other calls need to be \\ prefix free.
  if($Destination -match '^\+?\d+$')
  {
    $ThisDestination = ('\\{0}' -f $Destination)
  }
  else
  {
    $ThisDestination = $Destination
  }

  $MessageHTML = ("<PolycomIPPhone><Data priority=`"{0}`">tel:{1};line{2}</Data></PolycomIPPhone>" -f $Priority, $Destination, $LineId)

  Try {
    $null = Invoke-UcsPushWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'push' -Method Post -Body $MessageHTML -ContentType 'application/x-com-polycom-spipx' -ErrorAction Stop

    if($PassThru -eq $true) 
    {
        Start-Sleep -Seconds 1
        $ThisCall = Get-UcsCallStatus -IPv4Address $IPv4Address -ErrorAction SilentlyContinue
        $null = $OutputArray.Add($ThisCall)
    }
  }
  Catch
  {
    Write-Error "Couldn't start call to $Destination on $ThisIPv4Address."
  }
  }
  End
  {
    Return $OutputArray
  }

}


Function Send-UcsPushMessage 
{
  <#
      .SYNOPSIS
      Send a message to a VVX.

      .DESCRIPTION
      Sends an HTML webpage with a title and a message to the VVX for display. The function is currently hardcoded to restrict the length of the output to the amount a VVX 300 series phone can show.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Title
      The part of the message in large text.

      .PARAMETER Message
      The part of the message in small text. Message can be up to 69 characters.

      .PARAMETER Priority
      Defaults to 'Critical.' Lower priorities may not be shown on some phones.

      .EXAMPLE
      Send-Message -IPv4Address 192.168.1.20 -Title "Test" -Message "Message" -Priority Critical
      A message with the title "Test" and the message "Message" appears on 192.168.1.20

      .NOTES
      Additional configuration is required to run this. The phone's "Push" credentials must be set (this script defaults to using "UCSToolkit" for both), "Allow Push Messages" must be set to "Critical" or lower, and "Application Server Root URL" must be specified. HTTPS must be enabled using Set-UcsPushConnectionSettings. Additionally, in Skype for Business deployments, the script must be run from a pool server.
  #>
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Parameter(Mandatory,HelpMessage = 'Add help message for user')][String]$Title,
    [Parameter(Mandatory,HelpMessage = 'Add help message for user')][String]$Message,
  [ValidateSet('Critical','Important','High','Normal')][String]$Priority = 'Critical')

  #TODO: You can fit more content on the 400+ series because of their higher resolution. Heading up to 18 characters, message up to 69 on 310, heading up to 18, message up to 200 on 400+.
  #I only wrote code for the 300 series because whatever
  #I've just put this here so I remember it's an option.

  Begin
  {
    $MessageHTML = ("<PolycomIPPhone><Data priority=`"{0}`"><h1>{1}</h1>{2}</Data></PolycomIPPhone>" -f $Priority, $Title, $Message)
  }

  Process
  {
    Foreach($ThisIPv4Address in $IPv4Address)
    {
      Try
      {
        $Output = Invoke-UcsPushWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'push' -Method Post -Body $MessageHTML -ContentType 'text/xml' -ErrorAction Stop
        Write-Debug $Output
      } 
      Catch
      {
        Write-Error "Failed to send a Push message to $ThisIPv4Address."
      }
    }
  }
  
  End
  {
  
  }
}

Function Send-UcsPushCallAction 
{
  <#
      .SYNOPSIS
      Send a callaction to a VVX.

      .DESCRIPTION
      Sends a callaction to the phone via the Push API. Requires a functional REST API to retrieve the call's handle. Check this is working by running Get-UcsPushCallStatus.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Priority
      Describe parameter -Priority.

      .PARAMETER CallAction
      One or more CallActions from this list: 'EndCall','Answer','Reject','Ignore','MicMute','Hold','Resume','Transfer','Conference','Join','Split','Remove.'

      .EXAMPLE
      Send-CallAction -IPv4Address Value -Priority Value -CallAction Value
      Describe what this call does

      .NOTES
      Additional configuration is required to run this. The phone's "Push" credentials must be set (this script defaults to using "UCSToolkit" for both), "Allow Push Messages" must be set to "Critical" or lower, and "Application Server Root URL" must be specified. HTTPS must be enabled using Set-UcsPushConnectionSettings. Additionally, in Skype for Business deployments, the script must be run from a pool server.
  #>
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String]$IPv4Address,
    [ValidateSet('Critical','Important','High','Normal')][String]$Priority = 'Critical',
  [Parameter(Mandatory,HelpMessage = 'Add help message for user')][ValidateSet('EndCall','Answer','Reject','Ignore','MicMute','Hold','Resume','Transfer','Conference','Join','Split','Remove')][String]$CallAction,
  [Parameter(ValueFromPipelineByPropertyName)][String][ValidatePattern('^0x[a-f0-9]{7,8}$')]$CallHandle)

  $ThisIPv4Address = $IPv4Address
  if($CallHandle -match '^0x[a-f0-9]{7,8}$')
  {
    $ThisCallRef = $CallHandle
  }
  else
  {
    $ThisCallRef = (Get-UcsCallStatus -IPv4Address $ThisIPv4Address).CallHandle
  }
  $MessageHTML = ("<PolycomIPPhone><Data priority=`"{0}`">CallAction:{1};nCallReference={2}</Data></PolycomIPPhone>" -f $Priority, $CallAction, $ThisCallRef)

  Try {
    $null = Invoke-UcsPushWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'push' -Method Post -Body $MessageHTML -ContentType 'application/x-com-polycom-spipx' -ErrorAction Stop
  }
  Catch
  {
    Write-Error "Couldn't send $CallAction to $ThisIPv4Address."
  }

}

Function Send-UcsPushKeyPress 
{
  <#
      .SYNOPSIS
      Send a keypress to a VVX. Multiple keypresses can be strung together in an array and sent in the same command.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Priority
      The HTTP WebRequest API provides support for a "Priority" flag. The lower the setting, the less likely it is to be sent to the phone.

      .PARAMETER Key
      One or more keys from the following list: 'Line1','Line2','Line3','Line4','Line5','Line6','Line7','Line8','Line9','Line10',
      'Line11','Line12','Line13','Line14','Line15','Line16','Line17','Line18','Line19','Line20','Line21','Line22','Line23',
      'Line24','Line25','Line26','Line27','Line28','Line29','Line30','Line31','Line32','Line33','Line34','Line35','Line36',
      'Line37','Line38','Line39','Line40','Line41','Line42','Line43','Line44','Line45','Line46','Line47','Line48','Dialpad0',
      'Dialpad1','Dialpad2','Dialpad3','Dialpad4','Dialpad5','Dialpad6','Dialpad7','Dialpad8','Dialpad9','DialPadStar',
      'DialPadPound','Softkey1','Softkey2','Softkey3','Softkey4','Softkey5','VolDown','VolUp','Headset','Handsfree',
      'MicMute','Menu','Messages','Applications','Directories','Setup','ArrowUp','ArrowDown','ArrowLeft','ArrowRight',
      'Backspace','DoNotDisturb','Select','Conference','Transfer','Redial','Hold','Status','CallList'.

      .EXAMPLE
      Send-KeyPress -IPv4Address 192.168.1.20 -Key ('Dialpad4','Dialpad1','Dialpad1','Softkey2')
      Presses "411 (send)" on the remote phone in sequence.

      .NOTES
      Additional configuration is required to run this. The phone's "Push" credentials must be set (this script defaults to using "UCSToolkit" for both), "Allow Push Messages" must be set to "Critical" or lower, and "Application Server Root URL" must be specified. HTTPS must be enabled using Set-UcsPushConnectionSettings. Additionally, in Skype for Business deployments, the script must be run from a pool server.
  #>
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String]$IPv4Address,
    [ValidateSet('Critical','Important','High','Normal')][String]$Priority = 'Critical',
    [Parameter(Mandatory,HelpMessage = 'Add help message for user')][ValidateSet('Line1','Line2','Line3','Line4','Line5','Line6','Line7','Line8','Line9','Line10',
        'Line11','Line12','Line13','Line14','Line15','Line16','Line17','Line18','Line19','Line20','Line21','Line22','Line23',
        'Line24','Line25','Line26','Line27','Line28','Line29','Line30','Line31','Line32','Line33','Line34','Line35','Line36',
        'Line37','Line38','Line39','Line40','Line41','Line42','Line43','Line44','Line45','Line46','Line47','Line48','Dialpad0',
        'Dialpad1','Dialpad2','Dialpad3','Dialpad4','Dialpad5','Dialpad6','Dialpad7','Dialpad8','Dialpad9','DialPadStar',
        'DialPadPound','Softkey1','Softkey2','Softkey3','Softkey4','Softkey5','VolDown','VolUp','Headset','Handsfree',
        'MicMute','Menu','Messages','Applications','Directories','Setup','ArrowUp','ArrowDown','ArrowLeft','ArrowRight',
  'Backspace','DoNotDisturb','Select','Conference','Transfer','Redial','Hold','Status','CallList')][String[]]$Key)
    
  BEGIN {
    $ResultArray = New-Object -TypeName System.Collections.ArrayList

    #Need to start by building out the series of commands to run.
    [String]$KeysToPress = ''
    Foreach($ThisKey in $Key) 
    {
      $KeysToPress += ("Key:{0}`n" -f $ThisKey)
    }
    #$KeysToPress = $KeysToPress.Substring(0,(($KeysToPress.Length) - 2))

    $MessageHTML = ("<PolycomIPPhone><Data priority=`"{0}`">{1}</Data></PolycomIPPhone>" -f $Priority, $KeysToPress)
    Write-Debug -Message ('Will send {0}.' -f $MessageHTML)
  } PROCESS {
    Foreach($ThisIPv4Address in $IPv4Address) 
    {
      Try
      {
        $ThisResult = Invoke-UcsPushWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'push' -Method Post -Body $MessageHTML -ContentType 'application/x-com-polycom-spipx' -ErrorAction Stop
      }
      Catch
      {
        Write-Error ("Couldn't send {0} to {1}" -f ($Key -join ", "),$ThisIPv4Address)
      }
      $null = $ResultArray.Add($ThisResult)
    }
  } END {
    #Return $ResultArray
  }
}

Function Get-UcsPushScreenCapture 
{
  <#
      .SYNOPSIS
      Captures the main screen of the phone and returns the result as an image object.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .PARAMETER ScreenToCapture
      Describe parameter -ScreenToCapture.

      .EXAMPLE
      Get-ScreenCapture -IPv4Address Value -ScreenToCapture Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      Syntax source
      http://community.polycom.com/t5/VoIP/FAQ-How-can-I-create-a-Screen-Capture-of-the-phone-GUI/td-p/4713

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>
  Param(
    [Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [ValidateSet('Main','EM1','EM2','EM3','EM4','EM5','EM6','EM7','EM8','EM9')][String]$ScreenToCapture = 'Main'
  )
    
  BEGIN {
    Add-Type -AssemblyName System.Drawing
    $ImageArray = New-Object -TypeName System.Collections.ArrayList
    $ScreencaptureParameterName = 'up.screenCapture.enabled'

    #Select which screen to get using the API endpoint.
    $ThisApiEndpoint = 'captureScreen'
    if($ScreenToCapture -eq 'All') 
    {
      #This option was removed because the page is HTML, not just an image.
      $ThisApiEndpoint = $ThisApiEndpoint #No Change
    }
    elseif($ScreenToCapture -eq 'Main') 
    {
      $ThisApiEndpoint += '/mainScreen'
    }
    else 
    {
      $ThisEMScreen = $ScreenToCapture.Substring(2,1)            
      $ThisApiEndpoint += ('/em/{0}' -f $ThisEMScreen)
    }

  } PROCESS {
    Foreach ($ThisIPv4Address in $IPv4Address) 
    {
      $CurrentScreenCaptureSetting = Get-UcsPushParameter -IPv4Address $ThisIPv4Address -Parameter $ScreencaptureParameterName
      if(($CurrentScreenCaptureSetting | Where-Object -Property Parameter -EQ -Value $ScreencaptureParameterName).Value -ne '1') 
      {
        Set-UcsRestParameter -IPv4Address $ThisIPv4Address -Parameter $ScreencaptureParameterName -Value $true
      }

      Try 
      {
        #This needs to be rewritten to take advantage of the credential arrays.
        $ScreenCapture = Invoke-UcsPushWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint $ThisApiEndpoint -Credential (Get-UcsRestAPICredential)[0] 
        [Drawing.Image]$Image = $ScreenCapture.Content
        $null = $ImageArray.Add($Image)
      }
      Catch 
      {
        Write-Warning -Message "Couldn't get a screen capture. Check if screen capture is enabled in phone settings: Settings->Basic->Preferences->Screen Capture"
        Write-Debug -Message ('Error was: {0}' -f $_)
      }
    }
  } END {
    Return $ImageArray
  }
}
