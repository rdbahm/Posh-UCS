Function Get-UcsProvFTPFile 
{
  <#
      .SYNOPSIS
      Downloads a file by name from the specified server, with the specified credential. Returns the file name of the downloaded file, which is saved to the temporary folder.

      .LINK
      http://www.thomasmaurer.ch/2010/11/powershell-ftp-upload-and-download/
      https://social.technet.microsoft.com/Forums/scriptcenter/en-US/ff18a705-eeee-4ba7-bd3e-2fcc9fd5cbee/using-powershell-to-download-from-ftp-site-file-name-has-wildcard?forum=ITCG
  #>

  Param(
    [Parameter(Mandatory,HelpMessage = 'Add help message for user')][String]$Address,
    [Parameter(Mandatory,HelpMessage = 'Add help message for user')][System.Management.Automation.Credential()][pscredential]$Credential,
    [Parameter(Mandatory,HelpMessage = 'Add help message for user')][String]$Filename
  )

  $URI = ('{0}/{1}' -f $Address.Trim(), $Filename.Trim())
  $LocalSaveLocation = Join-Path -Path $env:TEMP -ChildPath $Filename

  $FTPRequest = New-Object -TypeName System.Net.WebClient
  $FTPRequest.Credentials = $Credential
  Try 
  {
    $FTPRequest.DownloadFile($URI,$LocalSaveLocation)
  }
  Catch 
  {
    Throw ("Couldn't download the file! Check credentials and filename. Requested URI was {0}." -f $URI)
  }

  Return $LocalSaveLocation
}


Function Get-UcsProvFTPFileList 
{
  <#
      .SYNOPSIS
      Downloads a file by name from the specified server, with the specified credential.
  #>

  Param(
    [Parameter(Mandatory,HelpMessage = 'Add help message for user')][String]$Address,
    [Parameter(Mandatory,HelpMessage = 'Add help message for user')][System.Management.Automation.Credential()][pscredential]$Credential
  )

  $URI = ('{0}' -f $Address)

  $FTPRequest = [Net.FtpWebRequest]::Create($URI)
  $FTPRequest = [Net.FtpWebRequest]$FTPRequest
  $FTPRequest.Method = [Net.WebRequestMethods+Ftp]::ListDirectory
  $FTPRequest.Credentials = $Credential
  $Response = $FTPRequest.GetResponse()
  $Reader = New-Object -TypeName IO.StreamReader -ArgumentList $Response.GetResponseStream()

  $Output = $Reader.ReadToEnd()
  $Reader.Close()
  $Response.Close()

  $Output = $Output.Split("`n") | Select-Object -Property @{
    Name       = 'Filename'
    Expression = {
      $_
    }
  } #Split the output by line.

  Return $Output
}