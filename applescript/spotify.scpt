-- /spotify command for textual IRC application
-- based on script for linkinus from agreeabledragon <recognize@me.com> (2011)

on textualcmd()
    set AppleScript's text item delimiters to ""
    set spotify_active to false
    set theString to "/me is not currently running Spotify."
    
    tell application "Finder"
        if (get name of every process) contains "Spotify" then set spotify_active to true
    end tell
    
    if spotify_active then
        set got_track to false
        
        tell application "Spotify"
            if player state is playing then
                set theTrack to name of the current track
                set theArtist to artist of the current track
                set theAlbum to album of the current track
                set isStarred to starred of the current track
                set theURL to spotify url of the current track
                set got_track to true
            end if
        end tell
        
        set theString to "/me is not playing anything in Spotify."
        
        if got_track then
            set fav to ""
            
            if isStarred then
                set fav to "one of my favorite tracks, "
            end if
            
            set theString to "/me is listening to ♫ " & theTrack & " ♫" & " by " & theArtist & ", from the album " & theAlbum & " via Spotify (" & theURL & ")"
            
        end if
    end if
    
    return theString
end textualcmd

