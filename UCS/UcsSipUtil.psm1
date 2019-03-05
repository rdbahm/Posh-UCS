Function Invoke-UcsSipRequest 
{
  Param(
    [Parameter(Mandatory,HelpMessage = '127.0.0.1')][String]$IPv4Address,
    [Int][ValidateRange(1,9999)]$CSeq = 1,
    [String][ValidateSet('OPTIONS','NOTIFY','INFO')]$Method = 'NOTIFY',
    [String]$Event = '',
    [Timespan]$Timeout = (Get-UcsConfig -API SIP).Timeout,
    [int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -API SIP).Retries,
    [int][ValidateRange(1,65535)]$Port = (Get-UcsConfig -API SIP).Port,
    [switch]$SkipParse
  )
  
  if( (Get-Module -Name nettcpip) -eq $null)
  {
    Try
    {
      Write-Debug "Attempting to load NetTCPIP..."
      if($PSVersionTable.PSEdition -eq "Desktop")
      {
        Import-Module -Name NetTCPIP -ErrorAction Stop
      }
      else
      {
        Import-Module -Name NetTCPIP -SkipEditionCheck -ErrorAction Stop
      }
    }
    Catch
    {
      Throw "Couldn't load NetTCPIP library. Error was: $_"
    }
  }
  
  $ThisIPv4Address = $IPv4Address
  $RandomRangeHigh = 99999999
  $RandomRangeLow  = 10000000
  
  Write-Debug "Performing initial setup for $ThisIpv4Address."
  $PhoneId = 'UCS'
  $SourceAddress = Find-NetRoute -RemoteIPAddress $ThisIPv4Address |
  Select-Object -First 1 |
  Select-Object -ExpandProperty IPAddress
  $SourcePort = Get-Random -Minimum 50000 -Maximum 50999
  $CallID = ('{0}-{1}' -f (Get-Random -Minimum $RandomRangeLow -Maximum $RandomRangeHigh), (Get-Random -Minimum $RandomRangeLow -Maximum $RandomRangeHigh))
  $CSeqString = ('{0} {1}' -f $CSeq, $Method)
  $SipTag = ('{0}-{1}' -f (Get-Random -Minimum $RandomRangeLow -Maximum $RandomRangeHigh), (Get-Random -Minimum $RandomRangeLow -Maximum $RandomRangeHigh))
  
  $SipMessage = @"
${Method} sip:${PhoneId}:${Port} SIP/2.0
Via: SIP/2.0/UDP ${SourceAddress}:${SourcePort}
From: <sip:${PhoneId}>;tag=${SipTag}
To: <sip:${ThisIPv4Address}:5060>
Call-ID: ${CallID}
CSeq: ${CSeqString}
Contact: <sip:${PhoneId}>
Content-Length: 0
"@

  if($Event.Length -gt 0) 
  {
    $SipMessage += "`nEvent: $Event"
  }

  $RemainingRetries = $Retries
  While($RemainingRetries -gt 0) {
    Write-Debug "Starting connection attempt for $ThisIPv4Address with $RemainingRetries retries remaining."
    $RemainingRetries--
    Try {
      $Parsed = $null
      
      $AsciiEncoded = New-Object -TypeName System.Text.ASCIIEncoding
      $Bytes = $AsciiEncoded.GetBytes($SipMessage)
		
      $Socket = New-Object -TypeName Net.Sockets.Socket -ArgumentList ([Net.Sockets.AddressFamily]::InterNetwork, 
        [Net.Sockets.SocketType]::Dgram, 
      [Net.Sockets.ProtocolType]::Udp)
		
      $ThisEndpoint = New-Object -TypeName System.Net.IPEndPoint -ArgumentList ([ipaddress]::Parse($SourceAddress), $SourcePort)
      $Socket.Bind($ThisEndpoint)
      $Socket.Connect($ThisIPv4Address,$Port)

      [Void]$Socket.Send($Bytes)
								
      [Byte[]]$buffer = New-Object -TypeName Byte[] -ArgumentList ($Socket.ReceiveBufferSize)
      $BytesReceivedError = $false
	  
      Write-Debug ('{0}: Initiating timeout of {1} seconds.' -f $IPv4Address,$Timeout.TotalSeconds)
      $IntegerTimeout = ($Timeout.TotalMilliseconds) * 1000
      if($Socket.Poll($IntegerTimeout,[Net.Sockets.SelectMode]::SelectRead))
      {
        $receivebytes = $Socket.Receive($buffer)
      } else {
        Write-Error ('{0}: Timeout of {1} seconds expired.' -f $IPv4Address,$Timeout.TotalSeconds) -ErrorAction Stop
      }
  
      [string]$PhoneResponse = $AsciiEncoded.GetString($buffer, 0, $receivebytes)
      
      if($SkipParse -eq $true) {
        $Parsed = $PhoneResponse
      } else {
        $Parsed = Convert-UcsSipResponse -SipMessage $PhoneResponse -ErrorAction Stop
      }

    } Catch {
      if($RemainingRetries -le 0) {
        Write-Error "An error occured while processing $ThisIPv4Address."
        Write-Debug "$_"
      } else {
        Write-Debug "Processing $ThisIPv4Address failed, $RemainingRetries remain."
      }
    } Finally {
      $Socket.Close()
    }
    
    if($Parsed -ne $null) {
      Break #Get out of the loop.
    }
  }
  
  Return $Parsed
}

Function Convert-UcsSipResponse 
{
  Param([Parameter(Mandatory)][String]$SipMessage)
  
  $PhoneResponse = $SipMessage.Split("`n")
  $ParameterList = New-Object -TypeName System.Collections.ArrayList
  
  $SipOK = $false
  $ObjectBuilder = New-Object -TypeName PSObject
  Foreach($Line in $PhoneResponse) 
  {
    if($Line -like '*SIP/2.0 200 OK*') 
    {
      $SipOK = $true
      Continue
    }
    elseif($SipOK -eq $false) 
    {
      Write-Error $Line
    }
    
    if($Line.Length -lt 3) 
    {
      Write-Debug -Message "Skipped Line `"$Line`""
      Continue
    }
    
    $ColonIndex = $Line.IndexOf(':')
    $ParameterName = $Line.Substring(0,$ColonIndex)
    $ParameterValue = ($Line.Substring($ColonIndex + 1)).Trim(' ')

    if($ParameterName -in $ParameterList)
    {
      Write-Debug ('{0} is already in the parameter set. Overriding original value "{1}" with new value "{2}".' -f $ParameterName,$ObjectBuilder.$ParameterName,$ParameterValue)
    }

    $null = $ParameterList.Add($ParameterName)
    
    $ObjectBuilder | Add-Member -MemberType NoteProperty -Name $ParameterName -Value $ParameterValue -Force
  }
  
  $ParsedSipMessage = $ObjectBuilder
  #Now we have an object with all the parameters that SIP gave back to us. We can further chop known ones up.

  Return $ParsedSipMessage  
}

<# Examples of SIP Messages:
    NOTIFY (for info): 
    $message = @"
    NOTIFY sip:${phoneid}:5060 SIP/2.0
    Via: SIP/2.0/UDP ${serverip}
    From: <sip:discover>;tag=1530231855-106746376154
    To: <sip:${ClientIP}:5060>
    Call-ID: ${call_id}
    CSeq: 1500 NOTIFY
    Contact: <sip:${phoneid}>
    Content-Length: 0

    NOTIFY (check-sync reboot)
    $message = @"
    NOTIFY sip:${phoneid}:5060 SIP/2.0
    Via: SIP/2.0/UDP ${serverip}
    From: <sip:${sip_from}>
    To: <sip:${phoneid}>
    Event: check-sync
    Call-ID: ${call_id}@${serverip}
    CSeq: 1300 NOTIFY
    Contact: <sip:${sip_from}>
    Content-Length: 0

#>

<# Example SIP Response: 
    SIP/2.0 200 OK
    Via: SIP/2.0/UDP 192.168.10.50:51234
    From: <sip:discover>;tag=1530231855-106746376154
    To: "John Smith" <sip:192.168.92.51:5060>;tag=2628867A-55AB4B1F
    CSeq: 1500 NOTIFY
    Call-ID: 07/10/201714:47:46msgtodiscover
    Contact: <sip:jsmith@example.com;opaque=user:epid:1234;gruu>
    User-Agent: Polycom/5.5.2.8571 PolycomVVX-VVX_310-UA/5.5.2.8571
    Accept-Language: en
    P-Preferred-Identity: "John Smith" <sip:jsmith@example.com>,<tel:+1234;ext=1234>
    Authorization: TLS-DSK qop="auth", realm="SIP Communications Service", opaque="1234", crand="12134", cnum="4", targetname="lyncserver.example.com", response="1234"
    Content-Length: 0
#>