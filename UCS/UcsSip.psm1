<## Phone Cmdlets ##>

Function Get-UcsSipPhoneInfo 
{
  <#
      .SYNOPSIS
      Collects as much information as possible about the requested Polycom phone via the SIP protocol.

      .DESCRIPTION
      Performs an OPTIONS request against the requested IP address, then returns an object with only the properties which were returned by the phone. Currently supports Label (Display Name), SIP address, LineUri, Firmware Version, and Model.

      .PARAMETER IPv4Address
      The IP address of the phone, such as 192.168.1.25.

      .EXAMPLE
      Get-UcsSipPhoneInfo -IPv4Address 192.168.1.25
      Returns information for the requested phone.

      .NOTES
      The model returned by this function may be different than the model returned by other APIs.
  #>


  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Switch]$IncludeUnreachablePhones)
  
  BEGIN {
    $AllResult = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    Foreach($ThisIPv4Address in $IPv4Address) 
    {
      Try 
      {
        $ThisResponse = Invoke-UcsSipRequest -IPv4Address $ThisIPv4Address -CSeq 1 -Method OPTIONS -ErrorAction Stop
      }
      Catch 
      {
        Write-Error -Message "Unable to get results from $ThisIPv4Address." -Category ConnectionError
      }
      
      
      <# Method to the madness description:
          We enumerate all the properties (Powershell categorizes them as NoteProperties), then iterate through each.
          Using a switch, we use special handling for certain properties, specifically User-Agent and P-Preferred-Identity.
          We then add all the data we collect into an object for reporting to the user.
          Most of the properties are from the SIP response itself, though we compute RegistrationStatus from the 
      #>
      Try 
      {
        $AllProperties = ($ThisResponse |
          Get-Member -ErrorAction Stop |
          Where-Object -Property MemberType -EQ -Value 'NoteProperty' |
        Select-Object -ExpandProperty Name)
      }
      Catch 
      {
        Write-Error -Message "No properties available for $ThisIPv4Address"
        Continue
      }
      $TheseProperties = New-Object -TypeName PSObject
      $Registered = $false
      Foreach($Property in $AllProperties) 
      {
        $Value = $ThisResponse.$Property
        Switch($Property) {
          'User-Agent' 
          {
            #This line looks like this from a Polycom VVX 310: Polycom/5.5.2.8571 PolycomVVX-VVX_310-UA/5.5.2.8571
            #Or like this from a RealPresence Trio: Polycom/5.4.3.2007 PolycomRealPresenceTrio-Trio_8800-UA/5.4.3.2007
            #Older firmware (5.3) looks a little different: PolycomVVX-VVX_310-UA/5.3.0.12768
            #Sample from 4.1.4: PolycomVVX-VVX_310-UA/4.1.4.7430_0004f2abcdef
            #This gives us version and model info.
            if($Value -like 'Polycom*') 
            {
              $Matches = $null
              $Version = $null
              $null = $Value -match '(?<=/)\d+\.\d+\.\d+\.\d+(?=[_\s])' #Version is preceded with a forward slash and followed by a space or an underscore.
              #If sec.tagSerialNo is set to 1, this will return the MAC address as well.
              
              Try
              {
                $Version = $Matches[0]
              }
              Catch
              {
                Write-Warning "Version string was in unexpected format: $Value"
              }
              
              $Matches = $null
              $Model = $null
              $null = $Value -match '(?<=\s?Polycom\w+-)[^_]+_[^-]+' #Polycom's format seems to be PolycomMODELNAME-MODELNAME_MODELNUMBER-UA.
              $Model = $Matches[0]
              $Model = $Model.Replace('_',' ')
              if($Model -like '*Trio*') 
              {
                #Ugly workaround to get the Trio to match names properly.
                $Model = ('RealPresence {0}' -f $Model)
              }
              
              Try 
              {
                $Matches = $null
                $MacAddress = $null
                $null = $Value -match '(?<=_)[a-f0-9]{12}'
                $MacAddress = $Matches[0]
              }
              Catch 
              {
                Write-Debug -Message "Couldn't get MAC address for $ThisIPv4Address."
              }
              
              $TheseProperties | Add-Member -MemberType NoteProperty -Name Model -Value $Model
              $TheseProperties | Add-Member -MemberType NoteProperty -Name FirmwareRelease -Value $Version

              
              if($MacAddress -ne $null) 
              {
                $TheseProperties | Add-Member -MemberType NoteProperty -Name MacAddress -Value $MacAddress
              }
            }
          }
          'P-Preferred-Identity' 
          {
            Write-Debug -Message 'Getting identity info'
            $Registered = $true
            if($Value -match "^`".+`" <sip:.+>(,<tel:.+>)?") 
            {
              Write-Debug -Message 'Identity info in parseable format.'
              #Actual value looks like: "John Smith" <sip:john@smith.com>,<tel:+15555555555;ext=55555> in Lync base profile when signed in.
              #If a user doesn't have a LineURI, it'll look like: "John Smith" <sip:john@smith.com>
              $Matches = $null
              $null = $Value -match 'sip:.+@.+\.[^>]+(?=>)'
              $SipAddress = $Matches[0]
              $Matches = $null
              $null = $Value -match "^`"[^`"]+`"" #Find the display name.
              $DisplayName = $Matches[0].Trim('"')
              
              $LineUri = ''
              if($Value -match "^`".+`" <sip:.+>,<tel:.+>") 
              {
                $Matches = $null
                $null = $Value -match '(?<=<)tel:[^>]+(?=>)'
                $LineUri = $Matches[0]
              }
              
              $TheseProperties | Add-Member -MemberType NoteProperty -Name SipAddress -Value $SipAddress
              $TheseProperties | Add-Member -MemberType NoteProperty -Name Label -Value $DisplayName
              $TheseProperties | Add-Member -MemberType NoteProperty -Name LineUri -Value $LineUri
            }
          }
          'Authorization' 
          { 
            if($Value -like '*targetname=*') 
            {
              $Matches = $null
              $null = $Value -match "(?<=targetname=`")[^`"]+(?=`")"
              $Server = $Matches[0]
              
              $TheseProperties | Add-Member -MemberType NoteProperty -Name Server -Value $Server
            }
          } default 
          {
            Write-Debug -Message "$Property`: This SIP property is not currently supported. Value was $Value"
          }
        }
      }
      
      if(($TheseProperties | Get-Member -MemberType NoteProperty | Measure-Object | Select-Object -ExpandProperty Count) -eq 0 -and $IncludeUnreachablePhones -eq $true) 
      {
        $TheseProperties | Add-Member -MemberType NoteProperty -Name Registered -Value $Registered
      }
      
      if($TheseProperties -ne $null) 
      {
        $TheseProperties | Add-Member -MemberType NoteProperty -Name IPv4Address -Value $ThisIPv4Address
        $null = $AllResult.Add($TheseProperties)
      }
    }
  } END {
    Return $AllResult
  }
}

Function Restart-UcsSipPhone 
{
  <#
      .SYNOPSIS
      Requests a restart of the specified phone or phones.

      .DESCRIPTION
      Sends a NOTIFY message with the event "check-sync." This invokes a restart on properly configured Polycom phones. 

      .PARAMETER IPv4Address
      The IP address of the target phone.

      .PARAMETER PassThru
      Returns the SIP response message.

      .NOTES
      voIpProt.SIP.specialEvent.checkSync.alwaysReboot must be set to 1 for this to function.

      .LINK
      http://community.polycom.com/t5/VoIP/FAQ-Reboot-the-Phone-remotely-or-via-the-Web-Interface/td-p/4239
  #>


  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Switch]$PassThru)
  
  BEGIN {
    $ResultObject = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    Foreach ($ThisIPv4Address in $IPv4Address) 
    {
      if($PSCmdlet.ShouldProcess(('{0}' -f $ThisIPv4Address))) 
      {
        $null = $ResultObject.Add((Invoke-UcsSipRequest -IPv4Address $ThisIPv4Address -Method NOTIFY -Event 'check-sync' -ErrorAction Stop))
      }
    }
  } END {
    if($PassThru -eq $true) 
    {
      Return $ResultObject
    }
  }
}

Function Test-UcsSipModule {
  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address)
  <#
      .SYNOPSIS
      Tests the SIP functions of a VVX phone. Functions which cause impact (specifically, phone restart) are executed last.
  #>
  
  BEGIN {
  } PROCESS {
    Foreach ($ThisIPv4Address in $IPv4Address) 
    {
      
      Try
      {
        $PhoneInfoValues = Get-UcsSipPhoneInfo -IPv4Address $ThisIPv4Address -ErrorAction Stop
        #SIP should return server, SIP address, label, lineUri, Model, FirmwareRelease, MacAddress, Registered, and IPv4Address.
        #Of the return values, we can't depend on any value for server, SIPAddress, Label, LineUri, MacAddress, or Registered.
        #But, we can depend on Model, FirmwareRelease, and IPv4Address.
        #We'll also check if any returned results for the others are valid.
        
        if($PhoneInfoValues.Model.Length -lt 3)
        {
          Write-Error "Get-UcsSipPhoneInfo: $ThisIPv4Address provided no valid information for model." -ErrorAction Continue
        }
        if($PhoneInfoValues.FirmwareRelease -notmatch '(\d+[A-Z]?\.){3}\d{4,}[A-Z]*(\s.+)?')
        {
          Write-Error "Get-UcsSipPhoneInfo: $ThisIPv4Address provided an invalid firmware release." -ErrorAction Continue
        }
        if($PhoneInfoValues.IPv4Address -notmatch '^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')
        {
          Write-Error "Get-UcsSipPhoneInfo: $ThisIPv4Address provided an invalid IPv4 Address." -ErrorAction Continue
        }
        
        if($PhoneInfoValues.MacAddress.Length -gt 0)
        {
          if($PhoneInfoValues.MacAddress -notmatch '[A-Fa-f0-9]{12}')
          {
            Write-Error "Get-UcsSipPhoneInfo: $ThisIPv4Address provided an invalid MacAddress." -ErrorAction Continue
          }
        }
      }
      Catch
      {
        Write-Warning "Get-UcsSipPhoneInfo: $ThisIPv4Address failed to get all data."
      }
      
      if($PSCmdlet.ShouldProcess(('{0}' -f $ThisIPv4Address))) 
      {
        #Testing Restart-UcsSipPhone. It's difficult to be sure using only SIP that a phone has restarted - so we just look to see that no errors were returned.
        #In addition, the phone only restarts if it's set to restart on a check-sync so reporting a failure here would be unwise.
        Try
        {
          $null = Restart-UcsSipPhone -IPv4Address $ThisIPv4Address -ErrorAction Stop -Confirm:$false
        }
        Catch
        {
          Write-Warning "Restart-UcsSipPhone: $ThisIPv4Address threw an error when restart was requested: $_"
        }
      }
    }
  } END {
  }
}