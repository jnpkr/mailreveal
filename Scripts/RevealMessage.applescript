on run argv
	if (count of argv) is 0 then error "Expected an operation."

	set operation to item 1 of argv
	if operation is "position-current-message" then
		if (count of argv) is not 3 then error "Expected message ID and viewer ID."
		return positionCurrentMessage(item 2 of argv, item 3 of argv as integer)
	end if

	if operation is "select-message" then
		if (count of argv) is not 4 then error "Expected library ID, message ID, and viewer ID."
		return selectKnownMessage(item 2 of argv as integer, item 3 of argv, item 4 of argv as integer)
	end if

	if operation is "select-mailbox" then
		if (count of argv) is not 4 then error "Expected account, mailbox, and viewer ID."
		return selectKnownMailbox(item 2 of argv, item 3 of argv, item 4 of argv as integer)
	end if

	if operation is "position-indexed-message" then
		if (count of argv) is not 6 then error "Expected library ID, message ID, account ID, mailbox path, and viewer ID."
		return positionIndexedMessage(item 2 of argv as integer, item 3 of argv, item 4 of argv, item 5 of argv, item 6 of argv as integer)
	end if

	error "Unknown operation “" & operation & "”."
end run

on positionIndexedMessage(targetLibraryID, expectedMessageID, accountID, mailboxPath, targetViewerID)
	tell application "/System/Applications/Mail.app"
		set targetAccount to missing value
		try
			set targetAccount to first account whose id is accountID
		end try
		if targetAccount is missing value then error "Mail could not find the indexed account."

		set targetMailbox to my mailboxAtPath(targetAccount, mailboxPath)
		if targetMailbox is missing value then error "Mail could not find the indexed mailbox “" & mailboxPath & "”."

		set targetMessage to missing value
		try
			-- Mail returns this exact unique-ID object specifier for selected
			-- messages. Constructing it directly avoids a linear `whose id`
			-- scan of the mailbox.
			set targetMessage to «class mssg» id targetLibraryID of targetMailbox
		end try
		if targetMessage is missing value then error "Mail could not find the indexed message in its mailbox."

		set actualMessageID to message id of targetMessage
		if actualMessageID is not expectedMessageID then error "Mail’s Message-ID did not match the index."

		set targetViewer to missing value
		try
			set targetViewer to first message viewer whose id is targetViewerID
		end try
		if targetViewer is missing value then error "Mail could not find its main message viewer."

		set selected mailboxes of targetViewer to {targetMailbox}
		delay 0.1
		set selected messages of targetViewer to {targetMessage}
		activate
	end tell

	return actualMessageID
end positionIndexedMessage

on mailboxAtPath(targetAccount, mailboxPath)
	set pathParts to my splitText(mailboxPath, "/")
	set candidates to missing value
	tell application "/System/Applications/Mail.app" to set candidates to mailboxes of targetAccount
	set currentMailbox to missing value

	repeat with pathPart in pathParts
		set matchedMailbox to missing value
		tell application "/System/Applications/Mail.app"
			repeat with candidateMailbox in candidates
				if name of candidateMailbox is (pathPart as text) then
					set matchedMailbox to candidateMailbox
					exit repeat
				end if
			end repeat
		end tell
		if matchedMailbox is missing value then
			set currentMailbox to missing value
			exit repeat
		end if
		set currentMailbox to matchedMailbox
		tell application "/System/Applications/Mail.app" to set candidates to mailboxes of currentMailbox
	end repeat

	if currentMailbox is not missing value then return currentMailbox

	-- Some IMAP servers expose a URL hierarchy (for example INBOX/Archive)
	-- which Mail flattens in its scripting model. Fall back to the leaf name;
	-- the caller verifies both the numeric ID and RFC Message-ID afterwards.
	set leafName to item -1 of pathParts as text
	tell application "/System/Applications/Mail.app" to set topMailboxes to mailboxes of targetAccount
	repeat with topMailbox in topMailboxes
		set matchedMailbox to my findNamedMailbox(topMailbox, leafName)
		if matchedMailbox is not missing value then return matchedMailbox
	end repeat

	return missing value
end mailboxAtPath

on splitText(sourceText, delimiterText)
	set previousDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to delimiterText
	set parts to text items of sourceText
	set AppleScript's text item delimiters to previousDelimiters
	return parts
end splitText

on positionCurrentMessage(expectedMessageID, targetViewerID)
	set targetMessage to missing value
	repeat 30 times
		tell application "/System/Applications/Mail.app" to set selectedItems to selection
		if (count of selectedItems) is 1 then
			set candidateMessage to item 1 of selectedItems
			tell application "/System/Applications/Mail.app" to set candidateMessageID to message id of candidateMessage
			if candidateMessageID is expectedMessageID then
				set targetMessage to candidateMessage
				exit repeat
			end if
		end if
		delay 0.01
	end repeat
	if targetMessage is missing value then error "Mail’s resolver did not select the linked message."

	tell application "/System/Applications/Mail.app"
		set targetLibraryID to id of targetMessage
		set targetMailbox to mailbox of targetMessage
		set targetViewer to missing value
		try
			set targetViewer to first message viewer whose id is targetViewerID
		end try
		if targetViewer is missing value then error "Mail could not find its main message viewer."

		set selected mailboxes of targetViewer to {targetMailbox}
	end tell

	-- Mail updates the viewer asynchronously after changing mailboxes. This short
	-- pause is enough for its indexed message object to become addressable without
	-- running a mailbox search.
	delay 0.05

	tell application "/System/Applications/Mail.app"
		set viewerMessage to first message of targetViewer whose id is targetLibraryID
		-- With conversations enabled this positions the conversation row even when
		-- Mail declines to select the individual child until the row is expanded.
		set selected messages of targetViewer to {viewerMessage}
		activate
	end tell

	return targetLibraryID as text
end positionCurrentMessage

on selectKnownMessage(targetLibraryID, expectedMessageID, targetViewerID)
	set targetLibraryID to targetLibraryID as integer
	set targetViewerID to targetViewerID as integer

	tell application "/System/Applications/Mail.app"
		set targetViewer to missing value
		try
			set targetViewer to first message viewer whose id is targetViewerID
		end try
		if targetViewer is missing value then error "Mail could not find its main message viewer."

		set viewerMessage to «class mssg» id targetLibraryID of targetViewer
		set actualMessageID to message id of viewerMessage
		if actualMessageID is not expectedMessageID then error "Mail’s Message-ID did not match the index."
		set selected messages of targetViewer to {viewerMessage}
		activate
	end tell
	return actualMessageID
end selectKnownMessage

on selectKnownMailbox(accountName, mailboxName, targetViewerID)
	set targetViewerID to targetViewerID as integer

	tell application "/System/Applications/Mail.app"
		set targetAccount to missing value
		try
			set targetAccount to first account whose name is accountName
		end try
		if targetAccount is missing value then error "Mail could not find the account “" & accountName & "”."

		set targetMailbox to missing value
		try
			set targetMailbox to first mailbox of targetAccount whose name is mailboxName
		end try
		if targetMailbox is missing value then
			repeat with topMailbox in mailboxes of targetAccount
				set targetMailbox to my findNamedMailbox(topMailbox, mailboxName)
				if targetMailbox is not missing value then exit repeat
			end repeat
		end if
		if targetMailbox is missing value then error "Mail could not find the mailbox “" & mailboxName & "”."

		set targetViewer to missing value
		try
			set targetViewer to first message viewer whose id is targetViewerID
		end try
		if targetViewer is missing value then error "Mail could not find its main message viewer."

		set selected mailboxes of targetViewer to {targetMailbox}
		activate
	end tell
end selectKnownMailbox

on findNamedMailbox(candidateMailbox, mailboxName)
	tell application "/System/Applications/Mail.app"
		if name of candidateMailbox is mailboxName then return candidateMailbox

		set childMailboxes to every mailbox of candidateMailbox
	end tell

	repeat with childMailbox in childMailboxes
		set matchedMailbox to findNamedMailbox(childMailbox, mailboxName)
		if matchedMailbox is not missing value then return matchedMailbox
	end repeat

	return missing value
end findNamedMailbox
