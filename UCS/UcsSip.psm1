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
        Write-Error -Message "Unable to get results from $ThisIPv4Address."
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
      $TheseProperties = $null
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
              
              if($TheseProperties -eq $null) 
              {
                $TheseProperties = 1 | Select-Object -Property @{
                  Name       = 'Model'
                  Expression = {
                    $Model
                  }
                }, @{
                  Name       = 'FirmwareRelease'
                  Expression = {
                    $Version
                  }
                }
              }
              else 
              {
                $TheseProperties = $TheseProperties | Select-Object -Property *, @{
                  Name       = 'Model'
                  Expression = {
                    $Model
                  }
                }, @{
                  Name       = 'FirmwareRelease'
                  Expression = {
                    $Version
                  }
                }
              }
              
              if($MacAddress -ne $null) 
              {
                $TheseProperties = $TheseProperties | Select-Object -Property *, @{
                  Name       = 'MacAddress'
                  Expression = {
                    $MacAddress
                  }
                }
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
              $null = $Value -match '(?<=<sip:).+@.+\.[^>]+(?=>)'
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
              
              if($TheseProperties -eq $null) 
              {
                $TheseProperties = 1 | Select-Object -Property @{
                  Name       = 'SIPAddress'
                  Expression = {
                    $SipAddress
                  }
                }, @{
                  Name       = 'Label'
                  Expression = {
                    $DisplayName
                  }
                }, @{
                  Name       = 'LineUri'
                  Expression = {
                    $LineUri
                  }
                }
              }
              else 
              {
                $TheseProperties = $TheseProperties | Select-Object -Property *, @{
                  Name       = 'SIPAddress'
                  Expression = {
                    $SipAddress
                  }
                }, @{
                  Name       = 'Label'
                  Expression = {
                    $DisplayName
                  }
                }, @{
                  Name       = 'LineUri'
                  Expression = {
                    $LineUri
                  }
                }
              }
            }
          }
          'Authorization' 
          { 
            if($Value -like '*targetname=*') 
            {
              $Matches = $null
              $null = $Value -match "(?<=targetname=`")[^`"]+(?=`")"
              $Server = $Matches[0]
              
              if($TheseProperties -eq $null) 
              {
                $TheseProperties = 1 | Select-Object -Property @{
                  Name       = 'Server'
                  Expression = {
                    $Server
                  }
                }
              }
              else 
              {
                $TheseProperties = $TheseProperties | Select-Object -Property *, @{
                  Name       = 'Server'
                  Expression = {
                    $Server
                  }
                }
              }
            }
          } default 
          {
            Write-Debug -Message "$Property`: This SIP property is not currently supported. Value was $Value"
          }
        }
      }
      
      if($TheseProperties -eq $null -and $IncludeUnreachablePhones -eq $true) 
      {
        $TheseProperties = 1 | Select-Object -Property @{
          Name       = 'Registered'
          Expression = {
            $Registered
          }
        }
      }
      else 
      {
        $TheseProperties = $TheseProperties | Select-Object -Property *, @{
          Name       = 'Registered'
          Expression = {
            $Registered
          }
        }
      }
      
      if($TheseProperties -ne $null) 
      {
        $ThisResult = $TheseProperties | Select-Object -Property *, @{
          Name       = 'IPv4Address'
          Expression = {
            $ThisIPv4Address
          }
        }
        $null = $AllResult.Add($ThisResult)
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

      .EXAMPLE
      Restart-UcsSipPhone -IPv4Address Value -PassThru
      Describe what this call does

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
        $null = $ResultObject.Add((Invoke-UcsSipRequest -IPv4Address $ThisIPv4Address -Method NOTIFY -Event 'check-sync'))
      }
    }
  } END {
    if($PassThru -eq $true) 
    {
      Return $ResultObject
    }
  }
}
