# Format USB Windows
### Run PowerShell as Administrator, then Run:
```powershell
diskpart
```
Inside diskpart:
```cmd
list disk
Identify your USB by size, then substitute the correct number:
select disk 1
clean
create partition primary
format fs=ntfs quick label="USB"
assign
exit
```

> ⚠️ Double-check select disk — clean wipes everything on the selected disk instantly. Disk 0 is usually your system drive.


If you want FAT32 instead of NTFS (better compatibility with TVs, car stereos, Linux, etc.), replace the format line with:
```powershell
format fs=fat32 quick label="USB"
```
**Note:** FAT32 has a 4GB max file size limit. For large files, stick with NTFS or use exFAT:
```powershell
format fs=exfat quick label="USB"
```
After **assign**, the drive should appear in File Explorer immediately. Let me know if diskpart throws any errors.