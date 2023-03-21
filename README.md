# Cx1-support-bundle-logcsv
A powershell script to pull data out of cx1 support bundle .log files and put them into a .csv for sort/search

Usage:
1. unzip the support bundle into a folder
2. run: cx1logcsv.ps1 .\your_folder 
  - optional parameters: 
    -start "2020-01-01 00:00:00"
    -end "2030-01-01 00:00:00"
    -errlog $true
3. it will create a big .csv file with all of the .log files that had JSON format data, trying to split out into columns
4. bon apetit!

Requirements:
  Install-Module powershell-yaml
