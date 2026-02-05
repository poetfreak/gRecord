' gRecord - 1.04 A GTK3 tray screen recorder for Linux
' Uses ffmpeg for X11 and wf-recorder for Wayland
' Hopefully covers everything for everyone for a while.
' Requires amixer for microphone muting
'****************************************************************

' License: Freeware. Do what you want, Leave me credit somewhere.
' =============>>>> Created by Eric Sebasta <<<<=================
#include once "gtk/gtk3.bi"
#include once "crt/unistd.bi"
#include once "vbcompat.bi"
#inclib "gtk-3"
#inclib "gdk-3"
#inclib "glib-2.0"
#inclib "gobject-2.0"
#inclib "X11"

' TODO: make sure /usr/bin/amixer is there or end. we cant mute and
' will crash

'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
' Global widgets and state
Dim Shared As GtkStatusIcon Ptr tray_icon
Const SIGTERM = 15
Dim Shared As GPid record_pid = 0
Dim Shared As Boolean is_recording = FALSE
Dim Shared As Boolean mute_mic = FALSE
Dim Shared As Boolean muted_on_start = FALSE
Dim Shared As String save_folder

' Declare C kill function to avoid conflict with FreeBASIC Kill keyword
Declare Function sys_kill Alias "kill" (ByVal pid As Integer, ByVal sig As Integer) As Integer

' Config functions
Sub load_config()
    Dim As String config_file = Environ("HOME") & "/.config/gRecord.ini"
    save_folder = Environ("HOME") & "/Videos"
    Dim As Integer f = FreeFile
    Dim As String ln
    
    If Open(config_file For Input As #f) = 0 Then
        Do Until EOF(f)
            Line Input #f, ln
            If Left(ln, 9) = "mute_mic=" Then
                mute_mic = Val(Mid(ln, 10))
            ElseIf Left(ln, 12) = "save_folder=" Then
                save_folder = Mid(ln, 13)
            End If
        Loop
        Close #f
    End If
End Sub

Sub save_config()
    Dim As String config_dir = Environ("HOME") & "/.config"
    Dim As String config_file = config_dir & "/gRecord.ini"
    Dim As Integer f = FreeFile
    
    Shell("mkdir -p " & config_dir)
    
    If Open(config_file For Output As #f) = 0 Then
        Print #f, "mute_mic=" & Str(CInt(mute_mic))
        Print #f, "save_folder=" & save_folder
        Close #f
    End If
End Sub

' Update icon based on state
Sub update_icon()
    If is_recording Then
        gtk_status_icon_set_from_stock(tray_icon, GTK_STOCK_MEDIA_STOP)
        gtk_status_icon_set_tooltip_text(tray_icon, "RECORDING... Click to stop")
    Else
        gtk_status_icon_set_from_stock(tray_icon, GTK_STOCK_MEDIA_RECORD)
        gtk_status_icon_set_tooltip_text(tray_icon, "Click to start recording")
    End If
End Sub

' Callback when the recordmydesktop process exits
Sub on_child_watch CDecl (ByVal pid As GPid, ByVal status As gint, ByVal user_data As gpointer)
    g_spawn_close_pid(pid)
    record_pid = 0
    is_recording = FALSE
    
    If muted_on_start Then
        Shell("amixer set Capture cap")
        muted_on_start = FALSE
    End If
    
    ' Update UI
    update_icon()
    gtk_status_icon_set_tooltip_text(tray_icon, "Recording saved. Ready.")
End Sub

' Tray icon clicked (Toggle)
Sub on_tray_activate CDecl (ByVal icon As GtkStatusIcon Ptr, ByVal user_data As gpointer)
    If is_recording Then
        ' Stop Recording
        If record_pid <> 0 Then
            sys_kill(record_pid, SIGTERM)
            gtk_status_icon_set_tooltip_text(tray_icon, "Encoding... Please wait.")
            gtk_status_icon_set_from_stock(tray_icon, GTK_STOCK_FLOPPY)
        End If
    Else
        ' Start Recording
        ' Format: rec-mm-dd-yyyy-hh-mm.ogv (using nn for minutes in VB format)
        Dim As String filename = save_folder & "/rec-" & Format(Now, "mm-dd-yyyy-hh-nn-ss") & ".mp4"

        If mute_mic Then
            Shell("amixer set Capture nocap")
            muted_on_start = TRUE
        Else
            muted_on_start = FALSE
        End If
        
        Dim As ZString Ptr argv(0 To 15) ' Increased size for more args
        Dim As Integer argc = 0

        If LCase(Environ("XDG_SESSION_TYPE")) = "wayland" Then
            ' Wayland backend: wf-recorder
            argv(argc) = @"wf-recorder" : argc += 1
            argv(argc) = @"-a" : argc += 1 ' Capture audio
            argv(argc) = @"-f" : argc += 1
            argv(argc) = StrPtr(filename) : argc += 1
        Else
            ' X11 backend: ffmpeg
            argv(argc) = @"ffmpeg" : argc += 1
            argv(argc) = @"-f" : argc += 1
            argv(argc) = @"x11grab" : argc += 1
            argv(argc) = @"-i" : argc += 1
            argv(argc) = @":0.0" : argc += 1 ' TODO: Add display selection
            argv(argc) = @"-f" : argc += 1
            argv(argc) = @"alsa" : argc += 1
            argv(argc) = @"-i" : argc += 1
            argv(argc) = @"default" : argc += 1
            argv(argc) = StrPtr(filename) : argc += 1
        End If
        argv(argc) = NULL

        Dim As GError Ptr err_ = NULL
        Dim As Boolean success

        success = g_spawn_async(NULL, @argv(0), NULL, _
                                G_SPAWN_DO_NOT_REAP_CHILD Or G_SPAWN_SEARCH_PATH, _
                                NULL, NULL, @record_pid, @err_)

        If success = FALSE Then
            Dim As String err_msg = "Error: " & *err_->message
            gtk_status_icon_set_tooltip_text(tray_icon, StrPtr(err_msg))
            g_error_free(err_)
            If muted_on_start Then
                Shell("amixer set Capture cap")
                muted_on_start = FALSE
            End If
        Else
            is_recording = TRUE
            update_icon()
            g_child_watch_add(record_pid, @on_child_watch, NULL)
        End If
    End If
End Sub

' Quit menu item
Sub on_quit CDecl (ByVal widget As GtkWidget Ptr, ByVal user_data As gpointer)
    If record_pid <> 0 Then
        sys_kill(record_pid, SIGTERM)
    End If
    If muted_on_start Then
        Shell("amixer set Capture cap")
    End If
    save_config()
    gtk_main_quit()
End Sub

' Mute toggle
Sub on_mute_toggled CDecl (ByVal widget As GtkCheckMenuItem Ptr, ByVal user_data As gpointer)
    mute_mic = gtk_check_menu_item_get_active(widget)
    save_config()
End Sub

' Change folder dialog
Sub on_change_folder CDecl (ByVal widget As GtkWidget Ptr, ByVal user_data As gpointer)
    Dim As GtkWidget Ptr dialog = gtk_file_chooser_dialog_new("Select Save Folder", _
                                  NULL, _
                                  GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER, _
                                  GTK_STOCK_CANCEL, GTK_RESPONSE_CANCEL, _
                                  GTK_STOCK_OPEN, GTK_RESPONSE_ACCEPT, _
                                  NULL)
    
    gtk_file_chooser_set_current_folder(GTK_FILE_CHOOSER(dialog), StrPtr(save_folder))
    
    If gtk_dialog_run(GTK_DIALOG(dialog)) = GTK_RESPONSE_ACCEPT Then
        Dim As ZString Ptr folder = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog))
        save_folder = *folder
        g_free(folder)
        save_config()
    End If
    gtk_widget_destroy(dialog)
End Sub

' About dialog
Sub on_about CDecl (ByVal widget As GtkWidget Ptr, ByVal user_data As gpointer)
    Dim As GtkWidget Ptr dialog = gtk_message_dialog_new(NULL, _
                                  GTK_DIALOG_MODAL, _
                                  GTK_MESSAGE_INFO, _
                                  GTK_BUTTONS_OK, _
                                  !"GRecord Version 1.04\nGtk Record Desktop Utility\nFor X11 or Wayland compositors.\nCreated by Eric Sebasta\nPowered by FreeBASIC Compiler")
    Dim As GtkWidget Ptr action_area = gtk_dialog_get_action_area(GTK_DIALOG(dialog))
    gtk_widget_set_margin_bottom(action_area, 32)
    gtk_dialog_run(GTK_DIALOG(dialog))
    gtk_widget_destroy(dialog)
End Sub

' Right click menu
Sub on_popup_menu CDecl (ByVal icon As GtkStatusIcon Ptr, ByVal button As Guint, ByVal activate_time As Guint32, ByVal user_data As gpointer)
    Dim As GtkWidget Ptr menu = gtk_menu_new()
    
    Dim As GtkWidget Ptr mute_item = gtk_check_menu_item_new_with_label("Mute Microphone")
    gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(mute_item), mute_mic)
    g_signal_connect(mute_item, "toggled", G_CALLBACK(@on_mute_toggled), NULL)
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), mute_item)
    
    Dim As GtkWidget Ptr folder_item = gtk_menu_item_new_with_label("Set Save Folder")
    g_signal_connect(folder_item, "activate", G_CALLBACK(@on_change_folder), NULL)
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), folder_item)

    Dim As GtkWidget Ptr about_item = gtk_menu_item_new_with_label("About")
    g_signal_connect(about_item, "activate", G_CALLBACK(@on_about), NULL)
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), about_item)
    
    Dim As GtkWidget Ptr quit_item = gtk_menu_item_new_with_label("Quit")
    
    g_signal_connect(quit_item, "activate", G_CALLBACK(@on_quit), NULL)
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), quit_item)
    gtk_widget_show_all(menu)
    
    gtk_menu_popup(GTK_MENU(menu), NULL, NULL, NULL, NULL, button, activate_time)
End Sub

' Main entry
gtk_init(NULL, NULL)
load_config()

tray_icon = gtk_status_icon_new_from_stock(GTK_STOCK_MEDIA_RECORD)
gtk_status_icon_set_tooltip_text(tray_icon, "gRecord - Click to record")
g_signal_connect(tray_icon, "activate", G_CALLBACK(@on_tray_activate), NULL)
g_signal_connect(tray_icon, "popup-menu", G_CALLBACK(@on_popup_menu), NULL)

gtk_main()
