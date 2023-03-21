param (
    [Parameter(Position=0,mandatory=$true)]
    [string]$path
)

if ( -not (Test-Path -path $path) ) {
    Write-Host "Path $path does not exist."
    exit
}


Write-Host "Searching for all *.log files in $path"


$fileCount = 0
$lineCount = 0
$jsonLineCount = 0

$files = @{}

Get-ChildItem -Path .\ -Include "*.log" -Recurse | foreach-object {
    $fileCount ++

    $lines = Get-Content -Path $_.FullName
    $lineCount += $lines.Length
    
    $file = $_.FullName.Replace( $pwd, "" )
    $file_svc = $_.BaseName

    #if ( $file -match "static*" ) {
    #if ( $jsonLineCount -lt 100 ) {

    $jsonLines = @()

    $lines | foreach-object {
        if ($_.Length -gt 1 -and $_.SubString(0,1) -eq "{") {
            $jsonLineCount++
            $line = $_.Replace( "scanId", "scanID" )
            $js = ($line | ConvertFrom-Json)
            
            $loglevel = "$($js.level)"
            if ( $loglevel -eq "" ) {
                $loglevel = "$($js.status)"
            }

            $logtime = "$($js.time)"
            if ( $logtime -eq "" ) {
                $logtime = "$($js['@timestamp'])"
            }
            if ( $logtime -eq "" ) {
                $logtime = "$($js.timestamp)"
            }
            if ( $logtime -eq "" ) {
                $logtime = "$($js.ts)"
            }
            
            $logapp = "$($js.app)"
            if ( $logapp -eq "" ) {
                $logapp = "$($js.appName)"
            }
            if ( $logapp -eq "" ) {
                $logapp = "$($js.componentName)"
            }
            if ( $logapp -eq "" ) {
                $logapp = "$($js.serviceName)"
            }
            if ( $logapp -eq "" ) {
                $logapp = "$($js.issuingService)"
            }
            if ( $logapp -eq "" ) {
                $logapp = "$($js.name)"
            }
            if ( $logapp -eq "" ) {
                $logapp = "$($js.Namespace)"
            }

            $logmsg = "$($js.msg)"
            
            if ( $logmsg -eq "" ) {
                $logmsg = "$($js.message)"
            }
            if ( $logmsg -eq "" ) {
                $logmsg = "$($js.Message)"
            }

            $logerr = "$($js.err)"
            
            if ( $logerr -eq "" ) {
                $logerr = "$($js.error)"
            } 
            if ( $js.correlationId -ne $null ) {
                $logcorrelationId = "$($js.correlationId)"
            }
            if ( $js.stacktrace -ne $null ) {
                $logstacktrace = "$($js.stacktrace)"
            }


            $trimmed = $js | Select-Object -Property * -ExcludeProperty level,time,appName,msg,err,correlationId,stacktrace,app,issuingService,componentName,message,error,serviceName,`@timestamp,timestamp,ts,name,Namespace

            $logextra = ($trimmed | ConvertTo-Json).Replace( "`"", "'" )
            if ( $logextra -eq @"
{
    '*':  null
}
"@ 
            ) {
                $logextra = ""
            }

            if ( $logapp -eq "" ) {
                #Write-Host "Empty logapp for: $js"
                $logapp = $file_svc
            }

            if ( $logmsg -ne $null ) {
                $logmsg = $logmsg.Replace( """", "'" )
            }
            if ( $logstacktrace -ne $null ) {
                $logstacktrace = $logstacktrace.Replace( """", "'" )
            }
            if ( $logerr -ne $null ) {
                $logerr = $logerr.Replace( """", "'" )
            }

            $jsonLines += """$loglevel"";""$logtime"";""$logapp"";""$logmsg"";""$logerr"";""$logcorrelationId"";""$logstacktrace"";""$logextra"";"
            
        }
    }


    $files[$file] = $jsonLines
    
    #}  
}

Write-Host "Read $fileCount files with $lineCount lines of which $jsonLineCount were json"

"sep=;" | out-file "$path.csv"

"file;level;time;app;msg;err;correlationId;stack;extra;" | Out-File "$path.csv" -Append

$files.Keys | foreach-object {
    $k = $_
    $files[$k] | foreach-object {
        $js = $_
        "$k;$js;" | out-file "$path.csv" -Append 
    }
}