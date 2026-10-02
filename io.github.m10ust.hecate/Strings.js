.pragma library
// Hecate wizard strings — THE string table (M4 brief law: no user-facing
// string lives outside this file; cutting wording is editing one file).
//
// Voice (WIZARD.md, decided 2026-09-30): technical but easy for a newbie.
// Direct and to the point. No em dashes. No parenthetical asides, no
// colon-led reveals, no explaining the joke, no scolding.
//
// Keys marked [W] are verbatim from WIZARD.md's approved copy.
// Keys marked [N] are NEW copy drafted in that voice for screens
// WIZARD.md does not cover. They are listed separately in the M4 report
// for Seb to cut or approve.

var S = {

 // ---- shared chrome ----
 "wizardTitle": "SET UP BACKUPS", // [N]
 "step": "Step", // [N] "Step 2 of 6"
 "of": "of", // [N]
 "back": "Back", // [N]
 "next": "Continue", // [N]
 "cancel": "Cancel", // [N]
 "finish": "Done", // [N]
 "working": "Working", // [N]
 "measuring": "Measuring the folder. This walks every file and can take a while on a large folder.", // [N]

 // ---- step 1: source ----
 "sourceHeading": "Pick the folder to protect", // [N] frame for the [W] copy
 "sourceOpening": "Hecate keeps three copies of a folder you choose, on three destinations that fail independently. Pick the folder first. You will see how large it is before anything else happens.", // [W]
 "sourcePathLabel": "Folder", // [N]
 "sourceMeasured": "files", // [N] suffix: "1,234 files"
 "sourceJobLabel": "Name this backup", // [N]
 "sourceJobPlaceholder": "a short name, like photos",// [N]

 // ---- M5.5: the folder picker (addendum brief) ----
 "pickerBrowse": "Browse...", // [N]
 "pickerOpening": "Opening the folder chooser...", // [N]
 "pickerNothingPicked": "No folder chosen — pick one or type the path.", // [N]
 "pickerFault": "The folder chooser could not open ({error}). Type the path instead.", // [N]
 "pickerSshNoChooser": "A remote destination cannot use the folder chooser — type host:/path. The chooser only sees this machine's disks.", // [N]
 "capacityFreeLabel": "free", // [N]
 "capacityRatioPass": "{ratio}x the size of the folder, free on this destination.", // [N]
 "capacityRatioWarn": "Only {ratio}x the size of the folder is free here. Three corners need room to grow; under 3x means history gets short.", // [N]
 "capacityUnknown": "Free space on this destination could not be read; no number is shown rather than a guess.", // [N]
 "capacityRefuse": "This destination reports zero bytes free.", // [N]
 "sourceNotADir": "That is not a folder. Pick a folder that exists.", // [N]
 "sourceEmpty": "Type the path of the folder to protect.", // [N]

 // ---- corner steps (2, 3, 4) ----
 "cornerOneHeading": "Where should the first copy live?", // [W]
 "cornerOneBody": "A second drive is the fastest and the cheapest place to start. This is a default, not a rule. Any corner can be any kind of destination.", // [W]
 "cornerTwoHeading": "The second copy needs to survive whatever takes the first one.", // [W]
 "cornerThreeHeading": "The third copy is the one that survives your house. A machine you own over ssh, or a cloud account.", // [W]
 "cornerDestLabel": "Destination", // [N]
 "cornerLocalHint": "A folder path, like /mnt/backup/photos", // [N]
 "cornerSshHint": "user@host:/path, like bee:/srv/corners/photos", // [N]
 "cornerTransport": "Kind", // [N]
 "transportLocal": "A folder on this machine or a mounted drive", // [N]
 "transportSsh": "A machine you reach over ssh", // [N]
 "cornerCheckButton": "Check this destination", // [N]
 "cornerChecking": "Checking this destination against the source and the other corners.", // [N]
 "cornerRefuseHeading": "That destination is refused", // [N] frame for [W]
 "cornerRefuseBody": "That is the same physical disk as corner one. If that disk fails, you lose both copies at the same moment and you will not have a backup. Choose a different destination.", // [W]
 "cornerWarnHeading": "These destinations look like siblings", // [N] frame for [W]
 "cornerWarnBody": "These two destinations look like siblings, so there is a real chance they fail together at the same age. Continue if you know why they are separate.", // [W]
 "cornerWarnAck": "Continue anyway", // [N] the deliberate button
 "cornerWarnAckRecorded": "Your continue is recorded in the state file.", // [N]
 "cornerChooseOther": "Choose a different destination", // [N]
 "cornerUnknownHeading": "The destination cannot be read", // [N]
 "cornerDeviceLabel": "Device", // [N]
 "cornerIdentityModel": "model", // [N]
 "cornerIdentitySerial": "serial", // [N]
 "cornerIdentityTransport": "connection", // [N]
 "cornerIdentityUnknown": "unknown", // [N]
 "cornerReasonUnknown": "not readable", // [N]

 // ---- step 5: schedule ----
 "scheduleHeading": "Nightly at 02:00. If the machine was asleep, the next run catches up on its own.", // [W]
 "scheduleBody": "The schedule runs with systemd as your user account. The engine writes a timer per backup and removes it when the backup is deleted. The panel still tells the truth about how long it has been.", // [N]
 "scheduleHorizonLabel": "Call a corner stale after", // [N]
 "scheduleHorizonHours": "hours without a successful run", // [N]

 // ---- step 6: first run ----
 "firstRunHeading": "Ready to make the first copies", // [N]
 "firstRunTruth": "The first copy takes hours, not minutes, because it is writing every byte. You can close this panel. It resumes where it stopped.", // [W]
 "firstRunTruthDraft": "The first copy writes {size} to each corner, which takes longer than any run after it. You can close this panel. It resumes where it stopped.", // [N] — the old string keeps shipping until his word
 "firstRunStart": "Run it now", // [N]
 "firstRunLater": "Skip for now", // [N]
 "firstRunRunning": "Copying. You can close this panel.", // [N]
 "firstRunDone": "Three corners current. Last checked just now.", // [N]

 // ---- re-entry ----
 "reenterHeading": "Swap a corner, change the schedule, or add a second job. Nothing here rebuilds what already works.", // [W]
 "reenterNewJob": "Set up a new backup", // [N]
 "reenterEditCorner": "Point corner", // [N] + number + "elsewhere"
 "reenterButton": "RE-ENTER WIZARD", // [N] panel button into the wizard's re-entry door
 "reenterElsewhere": "elsewhere", // [N]
 "reenterChanged": "Corner moved. Its previous history does not travel. Run the job to seed the new destination.", // [N]
 "reenterHorizonChanged": "Horizon updated.", // [N]

 // ---- panel: verification (M5) ----
 "verifyButton": "Check the copies", // [N] list diff + manifest scrub, no copying
 "verifyRunning": "Checking. This reads every file in the newest snapshot.", // [N]
 "verifyDone": "Checked. Every copy matched its manifest.", // [N]
 "verifyFound": "Checked. A copy did not match. The reason is on its row.", // [N]

 // ---- generic errors ----
 "engineError": "The engine said no. The reason is below.", // [N]
 "nameTaken": "That name is already in use by another backup.", // [N]
 "nameNeeded": "Give the backup a name first.", // [N]
 "destNeeded": "Type a destination first.", // [N]
 "sshLater": "ssh corners need the key set up first. The check could not reach the machine.", // [N]
}
