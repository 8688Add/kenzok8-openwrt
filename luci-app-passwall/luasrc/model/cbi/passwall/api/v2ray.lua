module("luci.model.cbi.passwall.api.v2ray", package.seeall)
local fs = require "nixio.fs"
local sys = require "luci.sys"
local util = require "luci.util"
local i18n = require "luci.i18n"
local api = require "luci.model.cbi.passwall.api.api"

local v2ray_api = "https://api.github.com/repos/v2fly/v2ray-core/releases/latest"
local is_armv7 = false

function to_check(arch)
   local app_path = api.get_v2ray_path() or ""
    if app_path == "" then
        return {
            code = 1,
            error = i18n.translatef("You did not fill in the %s path. Please save and apply then update manually.", "V2ray")
        }
    end
    if not arch or arch == "" then arch = api.auto_get_arch() end

    local file_tree, sub_version = api.get_file_info(arch)
    if sub_version == "7" then is_armv7 = true end

    if file_tree == "" then
        return {
            code = 1,
            error = i18n.translate("Can't determine ARCH, or ARCH not supported.")
        }
    end

    if file_tree == "amd64" then file_tree = "64" end
    if file_tree == "386" then file_tree = "32" end

    local json = api.get_api_json(v2ray_api)

    if json.tag_name == nil then
        return {
            code = 1,
            error = i18n.translate("Get remote version info failed.")
        }
    end

    local now_version = api.get_v2ray_version()
    local remote_version = json.tag_name:match("[^v]+")
    local needs_update = api.compare_versions(now_version, "<", remote_version)
    local html_url, download_url

    if needs_update then
        html_url = json.html_url
        for _, v in ipairs(json.assets) do
            if v.name and v.name:match("linux%-" .. file_tree) then
                download_url = v.browser_download_url
                break
            end
        end
    end

    if needs_update and not download_url then
        return {
            code = 1,
            now_version = now_version,
            version = remote_version,
            html_url = html_url,
            error = i18n.translate("New version found, but failed to get new version download url.")
        }
    end

    return {
        code = 0,
        update = needs_update,
        now_version = now_version,
        version = remote_version,
        url = {html = html_url, download = download_url}
    }
end

function to_download(url)
    local app_path = api.get_v2ray_path() or ""
    if app_path == "" then
        return {
            code = 1,
            error = i18n.translatef("You did not fill in the %s path. Please save and apply then update manually.", "V2ray")
        }
    end
    if not url or url == "" then
        return {code = 1, error = i18n.translate("Download url is required.")}
    end

    sys.call("/bin/rm -f /tmp/v2ray_download.*")

    local tmp_file = util.trim(util.exec("mktemp -u -t v2ray_download.XXXXXX"))

    local result = api.exec(api.curl, {api._unpack(api.curl_args), "-o", tmp_file, url}, nil, api.command_timeout) == 0

    if not result then
        api.exec("/bin/rm", {"-f", tmp_file})
        return {
            code = 1,
            error = i18n.translatef("File download failed or timed out: %s", url)
        }
    end

    return {code = 0, file = tmp_file}
end

function to_extract(file, subfix)
    local app_path = api.get_v2ray_path() or ""
    if app_path == "" then
        return {
            code = 1,
            error = i18n.translatef("You did not fill in the %s path. Please save and apply then update manually.", "V2ray")
        }
    end

    if not file or file == "" or not fs.access(file) then
        return {code = 1, error = i18n.translate("File path required.")}
    end

    if sys.exec("echo -n $(opkg list-installed | grep -c unzip)") ~= "1" then
        api.exec("/bin/rm", {"-f", file})
        return {
            code = 1,
            error = i18n.translate("Not installed unzip, Can't unzip!")
        }
    end

    sys.call("/bin/rm -rf /tmp/v2ray_extract.*")
    local tmp_dir = util.trim(util.exec("mktemp -d -t v2ray_extract.XXXXXX"))

    local output = {}
    api.exec("/usr/bin/unzip", {"-o", file, "-d", tmp_dir},
             function(chunk) output[#output + 1] = chunk end)

    local files = util.split(table.concat(output))

    api.exec("/bin/rm", {"-f", file})

    return {code = 0, file = tmp_dir}
end

function to_move(file)
    local app_path = api.get_v2ray_path() or ""
    if app_path == "" then
        return {
            code = 1,
            error = i18n.translatef("You did not fill in the %s path. Please save and apply then update manually.", "V2ray")
        }
    end
    if not file or file == "" then
        sys.call("/bin/rm -rf /tmp/v2ray_extract.*")
        return {code = 1, error = i18n.translate("Client file is required.")}
    end

    if not arch or arch == "" then arch = api.auto_get_arch() end
    local file_tree, sub_version = api.get_file_info(arch)
    local t = ""
    sys.call("/etc/init.d/passwall stop")
    local result = nil
    if sub_version and sub_version == "7" then t = "_armv7" end
    result = api.exec("/bin/mv", { "-f", file .. "/v2ray" .. t, app_path }, nil, api.command_timeout) == 0
    sys.call("/bin/rm -rf /tmp/v2ray_extract.*")
    if not result or not fs.access(app_path) then
        return {
            code = 1,
            error = i18n.translatef("Can't move new file to path: %s", app_path)
        }
    end
    
    api.chmod_755(app_path)
    sys.call("/etc/init.d/passwall restart >/dev/null 2>&1 &")

    return {code = 0}
end
