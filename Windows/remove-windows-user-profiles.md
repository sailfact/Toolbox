# Removing User Profiles in Windows

## Via System Properties (GUI — Most Common)

1. Press **Win + R**, type `sysdm.cpl`, hit Enter
2. Go to the **Advanced** tab → under *User Profiles*, click **Settings**
3. Select the profile you want to delete → click **Delete**

> **Note:** You can't delete a profile that's currently logged in. The account must be signed out first.

---

## Via Settings (Windows 11)

1. Settings → **Accounts** → **Other users**
2. Click the account → **Remove** → confirm

This removes the account *and* optionally the profile data.

---

## Via PowerShell

List all profiles:

```powershell
Get-WmiObject -Class Win32_UserProfile | Select-Object LocalPath, SID, Loaded
```

Delete a specific profile by SID or path:

```powershell
$profile = Get-WmiObject -Class Win32_UserProfile | Where-Object { $_.LocalPath -like "*username*" }
$profile.Delete()
```

> Make sure `Loaded` is `False` before deleting — otherwise it'll error out.

---

## Manually via Registry (Last Resort / Cleanup)

If a profile is orphaned (user account deleted but folder remains):

1. Open `regedit` → navigate to:
   `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList`
2. Find the SID key pointing to the stale profile path
3. Delete that key
4. Then manually delete the folder from `C:\Users\`

---

## Things to Keep in Mind

- The built-in **Administrator** and **Default** profiles can't be deleted this way
- Deleting a profile removes everything in that user's `C:\Users\<name>` folder — back up anything needed first
- If you're seeing the *temporary profile* issue (Event ID 1511), that's a separate registry fix in `ProfileList`
