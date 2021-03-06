<#       
    .DESCRIPTION
        Script to enumerate OneDrive for Business Sites along with their data usage and date created. 

        The sample scripts are not supported under any Microsoft standard support 
        program or service. The sample scripts are provided AS IS without warranty  
        of any kind. Microsoft further disclaims all implied warranties including,  
        without limitation, any implied warranties of merchantability or of fitness for 
        a particular purpose. The entire risk arising out of the use or performance of  
        the sample scripts and documentation remains with you. In no event shall 
        Microsoft, its authors, or anyone else involved in the creation, production, or 
        delivery of the scripts be liable for any damages whatsoever (including, 
        without limitation, damages for loss of business profits, business interruption, 
        loss of business information, or other pecuniary loss) arising out of the use 
        of or inability to use the sample scripts or documentation, even if Microsoft 
        has been advised of the possibility of such damages.

        Original version - Credit to: https://gallery.technet.microsoft.com/scriptcenter/How-to-export-the-users-a996b16c

        Alejandro Lopez - alejanl@microsoft.com

    .PARAMETER AdminSiteUrl
        Specifies the URL of the SharePoint Online Administration Center site.
    .PARAMETER GlobalAdminUPN
        Specifies the username of the SharePoint Online global administrator that will be added to the personal sites collection administrators.
    .PARAMETER AdminPassword
        Specifies the password of the SharePoint Online global administrator that will be added to the personal sites collection administrators.
    .PARAMETER MySiteHostURL
        Specifies the location at which the personal sites are created.
	.PARAMETER ImportCSVFile
    	Specify a CSV file with list of users to query for their OD4B sites and get their storage. 
        The CSV file needs to have "LoginName" as the column header
    .PARAMETER  ExcelFilePath
        Specifies the path which the report will be stored in. If this parameter is empty, the report will be stored in current directorye
    .PARAMETER  FileName
        Specifies the file name which the report will be. If this parameter is empty, the default name is OneDriveProUsage.csv
    .EXAMPLE
        .\Get-ODBUsage.ps1 -AdminSiteUrl https://domain-admin.sharepoint.com -GlobalAdminUPN admin@domain.onmicrosoft.com -AdminPassword Password -MySiteHostURL https://domain-my.sharepoint.com -ImportCSVFile "c:\userslist.csv" 
	.EXAMPLE
        .\Get-ODBUsage.ps1 -AdminSiteUrl https://domain-admin.sharepoint.com -GlobalAdminUPN admin@domain.onmicrosoft.com -AdminPassword Password -MySiteHostURL https://domain-my.sharepoint.com -ExcelFilePath c:\dailyreport -FileName OneDriveUsage.csv
#>
[Cmdletbinding()]
Param (
    [String]$AdminSiteUrl = "https://tenant-admin.sharepoint.com",
    [String]$GlobalAdminUPN = "admin@tenant.onmicrosoft.com",
    [String]$AdminPassword = "password",
    [String]$MySiteHostURL = "https://tenant-my.sharepoint.com",
	
	[Parameter(mandatory=$false)]
    [String]$ImportCSVFile,

    [Parameter(Mandatory=$false)][ValidateScript({Test-Path $_ -PathType 'Container'})] 
    [string] $ExcelFilePath=$null,

    [Parameter(Mandatory=$false)]
    [string]$FileName="OneDriveForBusinessUsage.csv"
)

begin 
{
    Import-Module 'C:\Program Files\SharePoint Online Management Shell\Microsoft.Online.SharePoint.PowerShell' -WarningAction SilentlyContinue
    Import-Module MSOnline

    # Connect to SharePoint Online administration site
    $SecurePass = ConvertTo-SecureString -string $AdminPassword -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential $GlobalAdminUPN, $SecurePass
    $credentials = New-Object Microsoft.SharePoint.Client.SharePointOnlineCredentials($GlobalAdminUPN, $SecurePass)
    Connect-SPOService -Url $AdminSiteUrl -Credential $Credential

    [regex]$reg = "(?<=@).+"
    $UsersDomainName = $reg.Match($GlobalAdminUPN).Value

    $MySitesLocation = $MySiteHostURL + "/personal/"    
    if($ExcelFilePath -eq "")
    {
        $ExcelFilePath = Split-Path -parent $MyInvocation.MyCommand.Definition
    }
    $ExcelFileFullPath = $ExcelFilePath + "\" + $FileName
	
	If($ImportCSVFile){
		If(Test-Path $ImportCSVFile){
			
			$UsersLogin = Import-Csv $ImportCSVFile | %{$_.LoginName}
			Write-Host "Using csv file with user count: $($UsersLogin.count)" -ForegroundColor Yellow
	    }
		else{
			Write-Host "$($ImportCSVFile) file not found."
		}
	}
	Else{
		$UsersLogin = Get-SPOUser -Site $MySiteHostURL | ForEach-Object {$_.LoginName}
	}	
}

process 
{
    $PersonalSites = New-Object 'System.Collections.Generic.List[System.String]'
    # Filter out login names that do not belong to the target user domain.
    foreach ($UserLogin in $UsersLogin) {
        #if ($UserLogin.EndsWith($UsersDomainName)) {
        
            $PersonalSites.Add($MySitesLocation + $UserLogin.Replace(".", "_").Replace("@", "_"))
        
    }

    $CountResult = @()
    foreach ($PersonalSite in $PersonalSites) 
    {
        $error.Clear()
        
        Write-Host "Checking personal site: $PersonalSite" 
        try{
            $null = Set-SPOUser -Site $PersonalSite -LoginName $GlobalAdminUPN -IsSiteCollectionAdmin $true 
        }
        catch{
            #$Error = $true
            #Do not collect errors
            #$GroupCountObject = New-Object PSObject
            #$GroupCountObject | Add-Member -membertype NoteProperty -Name "Display Name" -Value $reg.Match($PersonalSite).Value
            #$GroupCountObject | Add-Member -membertype NoteProperty -Name "Usage Size (MB)" -Value "n/a"
            #$CountResult += $GroupCountObject
        }
        If(-not $error){
            $Url = $PersonalSite + "/_api/site/usage"
            $request = [System.Net.WebRequest]::Create($Url)
            $request.Credentials = $Credentials
            $request.Headers.Add("X-FORMS_BASED_AUTH_ACCEPTED", "f")
            $request.Accept = "application/json;odata=verbose"
            [Microsoft.PowerShell.Commands.WebRequestMethod]$Method = [Microsoft.PowerShell.Commands.WebRequestMethod]::Get
            $request.Method=$Method
            $response = $request.GetResponse()
            $requestStream = $response.GetResponseStream()
            $readStream = New-Object System.IO.StreamReader $requestStream
            $data=$readStream.ReadToEnd()
            $results = $data | ConvertFrom-Json
            [regex]$reg = "(?<=$MySitesLocation)\w+"
			
			$Url = $PersonalSite + "/_api/web"
            $request = [System.Net.WebRequest]::Create($Url)
            $request.Credentials = $Credentials
            $request.Headers.Add("X-FORMS_BASED_AUTH_ACCEPTED", "f")
            $request.Accept = "application/json;odata=verbose"
            [Microsoft.PowerShell.Commands.WebRequestMethod]$Method = [Microsoft.PowerShell.Commands.WebRequestMethod]::Get
            $request.Method=$Method
            $response = $request.GetResponse()
            $requestStream = $response.GetResponseStream()
            $readStream = New-Object System.IO.StreamReader $requestStream
            $dataWeb =$readStream.ReadToEnd()
            $resultsWeb = $dataWeb | ConvertFrom-Json
			
            $GroupCountObject = New-Object PSObject
            $GroupCountObject | Add-Member -membertype NoteProperty -Name "Display Name" -Value $reg.Match($PersonalSite).Value
            $GroupCountObject | Add-Member -membertype NoteProperty -Name "URL" -Value $PersonalSite
            $GroupCountObject | Add-Member -membertype NoteProperty -Name "Usage Size (MB)" -Value $("{0:N2}" -f $($results.d.Usage.Storage/1Mb))
			$GroupCountObject | Add-Member -membertype NoteProperty -Name "Date Created" -Value $($resultsWeb.d.Created)
            $CountResult += $GroupCountObject
        }
    }
}

End
{
    #Write out to excel file and console
    $CountResult | sort "Usage Size (MB)" -Descending | %{$_} | export-csv $ExcelFileFullPath -NoTypeInformation
    Write-Host "CSV File Location: " -NoNewline; Write-Host $ExcelFileFullPath -ForegroundColor Yellow
    ""
    $CountResult | sort "Usage Size (MB)" -Descending | %{$_}
} 
 
