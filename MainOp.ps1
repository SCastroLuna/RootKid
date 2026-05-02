while($true){
  try { SystemHealthMonitor.exe }
  catch { Start-Sleep -Seconds 30 }
}