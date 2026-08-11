using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using Windows.Media.Control;
using Windows.Storage.Streams;

internal static class MusicSessionBridge
{
    private static readonly JavaScriptSerializer Json = new JavaScriptSerializer();

    private sealed class SessionSelection
    {
        public GlobalSystemMediaTransportControlsSession Session;
        public int SessionCount;
        public int SupportedSessionCount;
    }

    public static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        try
        {
            var result = RunAsync(args ?? new string[0]).GetAwaiter().GetResult();
            Console.WriteLine(Json.Serialize(result));
            return result.ContainsKey("success") && Convert.ToBoolean(result["success"]) ? 0 : 2;
        }
        catch (Exception error)
        {
            Console.WriteLine(Json.Serialize(new Dictionary<string, object>
            {
                { "success", false },
                { "found", false },
                { "error", error.GetType().Name + ": " + error.Message }
            }));
            return 1;
        }
    }

    private static async Task<Dictionary<string, object>> RunAsync(string[] args)
    {
        var action = args.Length > 0 ? (args[0] ?? "status").Trim().ToLowerInvariant() : "status";
        var manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
        var selection = SelectSession(manager);
        if (selection.Session == null)
        {
            return new Dictionary<string, object>
            {
                { "success", true },
                { "found", false },
                { "session_count", selection.SessionCount },
                { "supported_session_count", selection.SupportedSessionCount }
            };
        }

        if (action == "status")
        {
            var coverPath = args.Length > 1 ? args[1] : string.Empty;
            return await ReadStatusAsync(selection, coverPath);
        }

        bool commandResult;
        switch (action)
        {
            case "toggle":
                commandResult = await selection.Session.TryTogglePlayPauseAsync();
                break;
            case "play":
                commandResult = await selection.Session.TryPlayAsync();
                break;
            case "pause":
                commandResult = await selection.Session.TryPauseAsync();
                break;
            case "next":
                commandResult = await selection.Session.TrySkipNextAsync();
                break;
            case "previous":
                commandResult = await selection.Session.TrySkipPreviousAsync();
                break;
            case "seek":
                long milliseconds;
                if (args.Length < 2 || !long.TryParse(args[1], out milliseconds))
                    throw new ArgumentException("seek requires a position in milliseconds");
                commandResult = await selection.Session.TryChangePlaybackPositionAsync(Math.Max(0, milliseconds) * TimeSpan.TicksPerMillisecond);
                break;
            default:
                throw new ArgumentException("unknown command: " + action);
        }

        return new Dictionary<string, object>
        {
            { "success", commandResult },
            { "found", true },
            { "command", action }
        };
    }

    private static SessionSelection SelectSession(GlobalSystemMediaTransportControlsSessionManager manager)
    {
        var sessions = manager.GetSessions();
        var current = manager.GetCurrentSession();
        GlobalSystemMediaTransportControlsSession selected = null;
        var bestScore = int.MinValue;
        var supportedCount = 0;

        foreach (var session in sessions)
        {
            if (!IsSupportedSource(session.SourceAppUserModelId))
                continue;
            supportedCount++;
            var score = 100;
            var info = session.GetPlaybackInfo();
            if (info != null && info.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing)
                score += 1000;
            else if (info != null && info.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Paused)
                score += 300;
            if (current != null && string.Equals(current.SourceAppUserModelId, session.SourceAppUserModelId, StringComparison.OrdinalIgnoreCase))
                score += 80;
            if (score > bestScore)
            {
                selected = session;
                bestScore = score;
            }
        }

        return new SessionSelection
        {
            Session = selected,
            SessionCount = sessions.Count,
            SupportedSessionCount = supportedCount
        };
    }

    private static async Task<Dictionary<string, object>> ReadStatusAsync(SessionSelection selection, string coverPath)
    {
        var session = selection.Session;
        var properties = await session.TryGetMediaPropertiesAsync();
        var playback = session.GetPlaybackInfo();
        var timeline = session.GetTimelineProperties();
        var controls = playback == null ? null : playback.Controls;
        var duration = timeline.EndTime - timeline.StartTime;
        var coverWritten = false;

        if (!string.IsNullOrWhiteSpace(coverPath) && properties.Thumbnail != null)
            coverWritten = await WriteThumbnailAsync(properties.Thumbnail, coverPath);

        var source = session.SourceAppUserModelId ?? string.Empty;
        var status = playback == null ? "unknown" : playback.PlaybackStatus.ToString().ToLowerInvariant();
        var title = properties.Title ?? string.Empty;
        var artist = properties.Artist ?? string.Empty;
        var album = properties.AlbumTitle ?? string.Empty;
        var durationMs = Math.Max(0L, (long)duration.TotalMilliseconds);
        var positionMs = Math.Max(0L, (long)(timeline.Position - timeline.StartTime).TotalMilliseconds);

        return new Dictionary<string, object>
        {
            { "success", true },
            { "found", true },
            { "source_app", source },
            { "source_label", SourceLabel(source) },
            { "provider", SourceProvider(source) },
            { "title", title },
            { "artist", artist },
            { "album", album },
            { "playback_status", status },
            { "position_ms", Math.Min(positionMs, durationMs > 0 ? durationMs : positionMs) },
            { "duration_ms", durationMs },
            { "track_id", source + "|" + title + "|" + artist + "|" + durationMs },
            { "can_play", controls != null && controls.IsPlayEnabled },
            { "can_pause", controls != null && controls.IsPauseEnabled },
            { "can_next", controls != null && controls.IsNextEnabled },
            { "can_previous", controls != null && controls.IsPreviousEnabled },
            { "can_seek", controls != null && controls.IsPlaybackPositionEnabled },
            { "cover_written", coverWritten },
            { "cover_path", coverWritten ? coverPath : string.Empty },
            { "session_count", selection.SessionCount },
            { "supported_session_count", selection.SupportedSessionCount }
        };
    }

    private static async Task<bool> WriteThumbnailAsync(IRandomAccessStreamReference thumbnail, string coverPath)
    {
        try
        {
            var directory = Path.GetDirectoryName(coverPath);
            if (!string.IsNullOrEmpty(directory))
                Directory.CreateDirectory(directory);

            byte[] bytes;
            using (IRandomAccessStreamWithContentType randomStream = await thumbnail.OpenReadAsync())
            using (Stream input = randomStream.AsStreamForRead())
            using (var memory = new MemoryStream())
            {
                await input.CopyToAsync(memory);
                bytes = memory.ToArray();
            }

            if (bytes.Length == 0)
                return false;
            var temporaryPath = coverPath + ".tmp";
            File.WriteAllBytes(temporaryPath, bytes);
            if (File.Exists(coverPath))
                File.Delete(coverPath);
            File.Move(temporaryPath, coverPath);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static bool IsSupportedSource(string source)
    {
        var value = (source ?? string.Empty).ToLowerInvariant();
        return value.Contains("qqmusic") || value.Contains("cloudmusic") || value.Contains("netease") || value.Contains("music.163");
    }

    private static string SourceProvider(string source)
    {
        var value = (source ?? string.Empty).ToLowerInvariant();
        if (value.Contains("qqmusic"))
            return "qq";
        if (value.Contains("cloudmusic") || value.Contains("netease") || value.Contains("music.163"))
            return "netease";
        return "local";
    }

    private static string SourceLabel(string source)
    {
        switch (SourceProvider(source))
        {
            case "qq": return "QQ音乐";
            case "netease": return "网易云音乐";
            default: return "本地播放器";
        }
    }
}
