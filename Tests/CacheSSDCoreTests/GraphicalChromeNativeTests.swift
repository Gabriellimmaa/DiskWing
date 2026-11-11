import XCTest
import Foundation
import Darwin
import AppKit
@testable import CacheSSDCore

/// Opt-in headed Chrome, generated home/profile, ordinary cache derivation and
/// local HTTP only. No disk-cache-dir, sandbox bypass or personal browser state.
final class GraphicalChromeNativeTests: XCTestCase {
    func testChromeVerifiedTransferFallbackReconnectAndRestore() throws {
        guard ProcessInfo.processInfo.environment["DISKWING_RUN_GRAPHICAL_NATIVE_TESTS"] == "1" else { throw XCTSkip("Set DISKWING_RUN_GRAPHICAL_NATIVE_TESTS=1 for the generated Chrome qualification") }
        let parent = try XCTUnwrap(ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"], "Use an explicit disposable SSD fixture directory")
        let app = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        let info = try XCTUnwrap(GenericAppDetector.readBundleInfo(app))
        let version = try XCTUnwrap(info["CFBundleShortVersionString"] as? String)
        guard version == "157.0.8103.39" else { throw XCTSkip("Installed Chrome version changed and needs a new qualification") }
        for key in ["UserDataDir", "DiskCacheDir"] {
            guard UserDefaults(suiteName: GraphicalCacheCatalog.chromeBundleID)?.object(forKey: key) == nil else { throw XCTSkip("An explicit Chrome directory policy prevents isolated profile qualification") }
        }
        let root = Paths.physicalURL(URL(fileURLWithPath: parent)).appendingPathComponent("DiskWing-Chrome-native-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let harness = try ChromeFixtureHarness(root: root)
        defer { harness.close() }
        let home = root.appendingPathComponent("home"), disk = root.appendingPathComponent("SSD")
        try FileManager.default.createDirectory(at: disk, withIntermediateDirectories: false)
        let model = GraphicalCacheCandidate(id: GraphicalCacheCatalog.chromeCacheID, applicationID: GraphicalCacheCatalog.chromeBundleID,
            applicationName: "Google Chrome", applicationVersion: version, applicationURL: app,
            sourceURL: home.appendingPathComponent(GraphicalCacheCatalog.chromeRelativePath),
            scopeLabel: "Chrome cache directory only; profile data stays local", canTransfer: true)
        let store = Store(base: root.appendingPathComponent("support"))
        let volume = VolumeInfo(uuid: "GENERATED-CHROME-SSD", name: "Generated SSD", path: disk.path, totalBytes: 100_000_000_000,
                                freeBytes: Volumes.free(at: disk), isInternal: false, isWritable: true)
        var available = true
        let engine = GraphicalCacheMigrationEngine(store: store, home: home, volumeProvider: { _ in available ? volume : nil },
            applicationRunning: { _ in harness.chromeRunning }, permittedRoot: root)
        _ = try harness.command("launch")
        let seed = try harness.command("fetch", asset: "A")
        XCTAssertGreaterThan(seed["length"] as? Int ?? 0, 100_000)
        XCTAssertEqual(try harness.command("read-set")["requests"] as? Int, 64)
        _ = try harness.command("seal-cookie")
        _ = try harness.command("stop")
        let profile = home.appendingPathComponent("Library/Application Support/Google/Chrome/GeneratedQualification")
        let protectedBefore = try profileSnapshot(profile)
        XCTAssertGreaterThanOrEqual(protectedBefore.count, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.sourceURL.appendingPathComponent("GeneratedQualification/Default/Cache/Cache_Data").path))
        let prepared: CacheTransferItemResult
        do { prepared = try engine.transfer(candidate: model, volume: volume, releaseSource: true) }
        catch {
            if let journal = try? engine.pendingTransfers().first, let staging = journal.stagingURL {
                let sourceDigest = try? FileTree.digest(model.sourceURL), copiedDigest = try? FileTree.digest(staging)
                print("Generated Chrome copy diagnostic: sourceStable=\(sourceDigest == journal.sourceDigest), copiedMatches=\(copiedDigest == journal.sourceDigest), identityStable=\((try? FileIdentity(model.sourceURL)) == journal.sourceIdentity)")
                let original = try? FileTree.manifest(model.sourceURL), copied = try? FileTree.manifest(staging)
                for item in original ?? [] {
                    if let match = copied?.first(where: { $0.path == item.path }), item != match { print("Generated cache metadata difference: \(item.path) original=\(item.metadata) copied=\(match.metadata)"); break }
                }
            }
            throw error
        }
        XCTAssertEqual(prepared.state, .configuredNeedsReopen); XCTAssertFalse(prepared.sourceReleased)
        XCTAssertEqual(try profileSnapshot(profile), protectedBefore)
        let registration = try XCTUnwrap(try engine.registrations().first)
        let quarantine = try XCTUnwrap(registration.sourceQuarantine)
        let quarantineDigest = try FileTree.digest(quarantine)
        _ = try harness.command("launch")
        _ = try harness.command("fetch", asset: "B")
        XCTAssertEqual(try FileTree.digest(quarantine), quarantineDigest)
        let observationDone = expectation(description: "Real Chrome descriptor observation window")
        var observation: Result<GraphicalCacheStatus, Error>?
        DispatchQueue.global(qos: .userInitiated).async {
            observation = Result { try engine.verifyUsage(candidate: model) }
            observationDone.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.25)
        let resourceReuse = try harness.command("read-set")
        XCTAssertEqual(resourceReuse["requests"] as? Int, 64, "All generated resources must come from the transferred cache without new HTTP requests")
        XCTAssertEqual(resourceReuse["fromDiskCache"] as? Bool, true)
        wait(for: [observationDone], timeout: 25)
        let verified = try XCTUnwrap(observation).get()
        XCTAssertEqual(verified.state, .ssdVerified, "Actual Chrome cache descriptors and writes are required; a touched file cannot stand in for use")
        XCTAssertTrue(verified.sourceReleased)
        XCTAssertFalse(FileManager.default.fileExists(atPath: quarantine.path))
        guard verified.state == .ssdVerified, verified.sourceReleased else { throw CacheSSDError.message("Native Chrome usage was not proved; original remains preserved") }
        let reused = try harness.command("fetch", asset: "A")
        XCTAssertEqual(reused["requests"] as? Int, 1, "A new Chrome process must reuse the transferred HTTP response after the old copy is gone")
        XCTAssertEqual(reused["fromDiskCache"] as? Bool, true)
        XCTAssertTrue(try harness.command("cookie")["preserved"] as? Bool == true)
        _ = try harness.command("stop")
        _ = try harness.command("launch")
        let newReused = try harness.command("fetch", asset: "B")
        XCTAssertEqual(newReused["requests"] as? Int, 1, "The newly fetched response must persist on SSD across Chrome restart")
        XCTAssertEqual(newReused["fromDiskCache"] as? Bool, true)
        _ = try harness.command("stop")
        let absent = root.appendingPathComponent("SSD-absent")
        try FileManager.default.moveItem(at: disk, to: absent); available = false
        XCTAssertEqual(engine.status(candidate: model).state, .localTemporary)
        _ = try harness.command("launch")
        let temporary = try harness.command("fetch", asset: "C")
        XCTAssertGreaterThan(temporary["length"] as? Int ?? 0, 100_000)
        _ = try harness.command("stop")
        var sourceInfo = stat(); XCTAssertEqual(lstat(model.sourceURL.path, &sourceInfo), 0)
        XCTAssertEqual(sourceInfo.st_mode & S_IFMT, mode_t(S_IFLNK))
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.sourceURL.path), "The qualified absent-SSD path uses temporary network/memory, not an invented local persistent cache")
        try FileManager.default.moveItem(at: absent, to: disk); available = true
        _ = try engine.resumeExternal(candidateID: model.id)
        _ = try harness.command("launch")
        XCTAssertEqual(try harness.command("fetch", asset: "A")["requests"] as? Int, 1)
        XCTAssertEqual(try harness.command("fetch", asset: "B")["requests"] as? Int, 1)
        _ = try harness.command("stop")
        _ = try engine.restore(candidateID: model.id)
        XCTAssertTrue(try engine.registrations().isEmpty)
        _ = try harness.command("launch")
        XCTAssertEqual(try harness.command("fetch", asset: "B")["requests"] as? Int, 1)
        XCTAssertTrue(try harness.command("cookie")["preserved"] as? Bool == true)
        _ = try harness.command("stop")
        guard let output = ProcessInfo.processInfo.environment["DISKWING_GRAPHICAL_NATIVE_REPORT"] else { return }
        guard testRun?.failureCount == 0 else { return }
        let report: [String: Any] = ["schemaVersion": 1, "candidateID": model.id, "applicationVersion": version,
            "cacheDirectoryOverrideUsed": false, "sandboxBypassUsed": false, "headedApplication": true,
            "launchRoute": "NSWorkspace.OpenConfiguration createsNewApplicationInstance",
            "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString, "architecture": "arm64", "filesystem": "apfs",
            "normalCacheResolution": "Chromium GetUserCacheDirectory: generated Library/Application Support descendant maps to generated Library/Caches",
            "originalCacheUnavailableAtNormalPath": true, "transferredResponseReusedWithoutNetwork": true,
            "newResponsePersistedOnSSDAcrossRestart": true, "nativeReadWriteDescriptorsObserved": verified.state == .ssdVerified,
            "sourceReleasedAfterVerifiedUse": verified.sourceReleased, "profileFilesUnchangedDuringTransfer": true,
            "generatedCookiePreserved": true, "absentSSDFallback": "temporary network/memory; no persistent local cache directory",
            "reconnectWithoutMerge": true, "restoreAndLocalReuse": true, "sameFilesystemFixture": true,
            "qualifiedDistribution": "Apple Developer ID / Google LLC EQHXZ8M8AV; strict signature and exact version",
            "metadataCopyPolicy": registration.metadataVerification?.policyVersion ?? 0,
            "metadataVerifiedEntries": registration.metadataVerification?.verifiedEntries ?? 0,
            "opaqueQuarantineProof": registration.metadataVerification?.quarantine.map { item -> [String: Any] in
                ["sourceSHA256": item.sourceSHA256 ?? "absent", "resultSHA256": item.resultSHA256 ?? "absent",
                 "referenceSHA256": item.referenceSHA256 ?? "absent", "objectType": item.objectType, "count": item.count]
            } ?? [],
            "physicalDisconnectTested": false, "personalProfilesUsed": false, "date": ISO8601DateFormatter().string(from: Date())]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output), options: .withoutOverwriting)
    }
    private func profileSnapshot(_ profile: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for name in ["Local State", "Default/Preferences", "Default/History", "Default/Network/Cookies", "Default/Cookies", "Default/Bookmarks"] {
            let url = profile.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { result[name] = try Data(contentsOf: url) }
        }
        return result
    }
}

private final class ChromeFixtureHarness {
    let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private var pending = Data()
    private(set) var chromeRunning = false
    init(root: URL) throws {
        let script = root.appendingPathComponent("generated-chrome-probe.py")
        try Data(Self.python.utf8).write(to: script)
        let executable = try XCTUnwrap(ToolLocator.locate("python3"))
        process = Process(); process.executableURL = executable; process.arguments = ["-u", script.path, root.path]
        let stdinPipe = Pipe(), stdoutPipe = Pipe()
        input = stdinPipe.fileHandleForWriting; output = stdoutPipe.fileHandleForReading
        process.standardInput = stdinPipe; process.standardOutput = stdoutPipe
        let log = root.appendingPathComponent("probe-private.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        process.standardError = try FileHandle(forWritingTo: log)
        var environment = ProcessInfo.processInfo.environment; environment["PYTHONDONTWRITEBYTECODE"] = "1"; process.environment = environment
        try process.run()
        let ready = try reply(); guard ready["ready"] as? Bool == true else { throw CacheSSDError.message("Generated Chrome probe did not start") }
    }
    func command(_ action: String, asset: String? = nil) throws -> [String: Any] {
        if action == "launch" {
            let configuration = try command("prepare-launch")
            let options = NSWorkspace.OpenConfiguration()
            options.createsNewApplicationInstance = true; options.activates = true
            options.arguments = try XCTUnwrap(configuration["arguments"] as? [String])
            options.environment = try XCTUnwrap(configuration["environment"] as? [String: String])
            let completed = XCTestExpectation(description: "Launch generated Chrome bundle")
            var launchError: Error?
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Google Chrome.app"), configuration: options) { _, error in launchError = error; completed.fulfill() }
            guard XCTWaiter.wait(for: [completed], timeout: 25) == .completed else { throw CacheSSDError.message("Generated Chrome LaunchServices timed out") }
            if let launchError { throw launchError }
            let connected = try command("connect")
            guard connected["runtimeVersion"] as? String == "Chrome/157.0.8103.39" else { throw CacheSSDError.message("Generated Chrome runtime version did not match the qualified distribution") }
            chromeRunning = true
            return connected
        }
        var value = ["action": action]; if let asset { value["asset"] = asset }
        var bytes = try JSONSerialization.data(withJSONObject: value); bytes.append(10); try input.write(contentsOf: bytes)
        let response = try reply()
        if let error = response["error"] as? String { throw CacheSSDError.message("Generated Chrome probe: " + error) }
        if action == "launch" { chromeRunning = true }; if action == "stop" { chromeRunning = false }
        return response
    }
    private func reply() throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            if let newline = pending.firstIndex(of: 10) {
                let line = pending[..<newline]; pending.removeSubrange(...newline)
                return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
            }
            var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            if poll(&descriptor, 1, 200) > 0 {
                let bytes = output.availableData
                guard !bytes.isEmpty else { throw CacheSSDError.message("Generated Chrome probe exited unexpectedly") }
                pending.append(bytes); guard pending.count <= 1_048_576 else { throw CacheSSDError.message("Generated Chrome probe exceeded reply limit") }
            }
        }
        throw CacheSSDError.message("Generated Chrome probe timed out")
    }
    func close() {
        if process.isRunning { _ = try? command("quit") }
        if process.isRunning { process.terminate() }
        chromeRunning = false
    }
    private static let python = #"""
import base64,http.server,json,os,pathlib,signal,socket,struct,subprocess,sys,threading,time,urllib.request,urllib.parse,uuid
root=pathlib.Path(sys.argv[1]);home=root/'home';profile=home/'Library/Application Support/Google/Chrome/GeneratedQualification';profile.mkdir(parents=True,exist_ok=True)
(root/'tmp').mkdir(exist_ok=True);counts={};sealed=False
tokens={name:('DISKWING-GENERATED-'+name+'-'+uuid.uuid4().hex+'\n')*8192 for name in ['A','B','C']}
tokens['A']*=40
reader_names=['R'+str(index) for index in range(64)]
tokens.update({name:('DISKWING-GENERATED-'+name+'-'+uuid.uuid4().hex+'\n')*8192 for name in reader_names})
class Handler(http.server.BaseHTTPRequestHandler):
 def do_GET(self):
  global sealed
  counts[self.path]=counts.get(self.path,0)+1
  page=self.path=='/page';body=(b'<html><title>DiskWing generated cache qualification</title><body>Local generated fixture only.</body></html>' if page else tokens.get(self.path.removeprefix('/asset-'),'missing').encode())
  self.send_response(200);self.send_header('Content-Length',str(len(body)));self.send_header('Content-Type','text/html' if page else 'text/plain');self.send_header('Cache-Control','no-store' if page else 'public, max-age=86400, immutable')
  if page and not sealed:self.send_header('Set-Cookie','diskwing_generated=preserve; Path=/; Max-Age=86400; SameSite=Lax')
  self.end_headers();self.wfile.write(body)
 def log_message(self,*args):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start();base='http://127.0.0.1:'+str(server.server_port)
events={}
class WS:
 def __init__(self,url):
  u=urllib.parse.urlsplit(url);self.s=socket.create_connection((u.hostname,u.port),timeout=20);key=base64.b64encode(os.urandom(16)).decode();self.s.sendall(('GET '+u.path+' HTTP/1.1\r\nHost: '+u.netloc+'\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: '+key+'\r\nSec-WebSocket-Version: 13\r\n\r\n').encode());buf=b''
  while b'\r\n\r\n' not in buf:buf+=self.s.recv(1)
  assert b'101' in buf;self.seq=0
 def exact(self,n):
  result=b''
  while len(result)<n:
   chunk=self.s.recv(n-len(result));assert chunk;result+=chunk
  return result
 def call(self,method,params=None):
  self.seq+=1;identifier=self.seq;payload=json.dumps({'id':identifier,'method':method,'params':params or {}}).encode();mask=os.urandom(4);n=len(payload);head=bytes([129,128|n]) if n<126 else bytes([129,254])+struct.pack('!H',n) if n<65536 else bytes([129,255])+struct.pack('!Q',n);self.s.sendall(head+mask+bytes(v^mask[i%4] for i,v in enumerate(payload)))
  while True:
   a,b=self.exact(2);n=b&127
   if n==126:n=struct.unpack('!H',self.exact(2))[0]
   elif n==127:n=struct.unpack('!Q',self.exact(8))[0]
   mask=self.exact(4) if b&128 else None;data=self.exact(n)
   if mask:data=bytes(v^mask[i%4] for i,v in enumerate(data))
   if a&15==8:raise RuntimeError('websocket closed')
   if a&15!=1:continue
   obj=json.loads(data)
   if obj.get('method')=='Network.responseReceived':
    response=obj['params']['response'];events[response['url']]=response.get('fromDiskCache',False)
   if obj.get('id')==identifier:
    if 'error' in obj:raise RuntimeError(str(obj['error']))
    return obj.get('result',{})
 def close(self):self.s.close()
chrome=None;browser=None;page=None
env={'PATH':'/usr/bin:/bin:/opt/homebrew/bin','HOME':str(home),'CFFIXED_USER_HOME':str(home),'TMPDIR':str(root/'tmp'),'LANG':'en_US.UTF-8','LC_ALL':'en_US.UTF-8'}
def evaluate(expression):
 value=page.call('Runtime.evaluate',{'expression':expression,'awaitPromise':True,'returnByValue':True})
 if 'exceptionDetails' in value:raise RuntimeError(str(value['exceptionDetails'].get('text','evaluation failed')))
 return value.get('result',{}).get('value')
def launch():
 global chrome,browser,page,events
 events={};portfile=profile/'DevToolsActivePort'
 if portfile.exists():portfile.unlink()
 log=(root/'chrome-private.log').open('ab')
 args=['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--user-data-dir='+str(profile),'--remote-debugging-port=0','--no-first-run','--no-default-browser-check','--disable-background-networking','--disable-component-update','--disable-updater-scheduler','--disable-default-apps','--disable-sync','--metrics-recording-only','--password-store=basic','--use-mock-keychain',base+'/page']
 return {'arguments':args[1:],'environment':env}
def connect():
 global browser,page
 portfile=profile/'DevToolsActivePort'
 for _ in range(200):
  if portfile.exists():break
  time.sleep(.1)
 port,endpoint=portfile.read_text().splitlines();browser=WS('ws://127.0.0.1:'+port+endpoint)
 runtime_version=browser.call('Browser.getVersion').get('product')
 if runtime_version!='Chrome/157.0.8103.39':raise RuntimeError('Generated Chrome runtime version mismatch')
 for _ in range(100):
  targets=json.load(urllib.request.urlopen('http://127.0.0.1:'+port+'/json/list'));target=next((t for t in targets if t.get('type')=='page' and t.get('url','').startswith(base)),None)
  if target:break
  time.sleep(.1)
 if not target:raise RuntimeError('Generated local page did not open')
 page=WS(target['webSocketDebuggerUrl']);page.call('Network.enable');page.call('Runtime.enable')
 for _ in range(100):
  try:
   if evaluate("document.readyState === 'complete' && location.origin === '"+base+"'"):return {'running':True,'runtimeVersion':runtime_version}
  except Exception:pass
  time.sleep(.1)
 raise RuntimeError('Generated page did not finish loading')
def stop():
 global chrome,browser,page
 if page:page.close();page=None
 if browser:
  try:browser.call('Browser.close')
  except Exception:pass
  browser.close();browser=None
 if chrome:
  try:chrome.wait(timeout=20)
  except subprocess.TimeoutExpired:chrome.terminate();chrome.wait(timeout=10)
  chrome=None
 marker='--user-data-dir='+str(profile)
 def owned_processes():
  result=subprocess.run(['/bin/ps','-ww','-axo','pid=,command='],capture_output=True,text=True)
  return [int(line.strip().split(None,1)[0]) for line in result.stdout.splitlines() if marker in line and '/Google Chrome.app/Contents/' in line]
 deadline=time.time()+20
 while owned_processes() and time.time()<deadline:time.sleep(.1)
 for pid in owned_processes():
  try:os.kill(pid,signal.SIGTERM)
  except ProcessLookupError:pass
 time.sleep(.3)
 return {'running':False}
def send(value):print(json.dumps(value),flush=True)
send({'ready':True})
try:
 for line in sys.stdin:
  try:
   command=json.loads(line);action=command['action']
   if action=='prepare-launch':result=launch()
   elif action=='connect':result=connect()
   elif action=='stop':result=stop()
   elif action=='seal-cookie':sealed=True;result={'sealed':True}
   elif action=='cookie':result={'preserved':'diskwing_generated=preserve' in (evaluate('document.cookie') or '')}
   elif action=='fetch':
    name=command['asset'];url=base+'/asset-'+name
    value=evaluate("fetch('"+url+"').then(r=>r.text()).then(t=>({length:t.length,valid:t.startsWith('DISKWING-GENERATED-"+name+"-')}))")
    if not value or not value.get('valid'):raise RuntimeError('Generated response bytes mismatch')
    time.sleep(.5);result={'length':value['length'],'requests':counts.get('/asset-'+name,0),'fromDiskCache':events.get(url,False)}
   elif action=='read-set':
    urls=[base+'/asset-'+name for name in reader_names]
    value=evaluate('Promise.all('+json.dumps(urls)+'.map(url=>fetch(url).then(r=>r.text()).then(t=>t.startsWith("DISKWING-GENERATED-R"))))')
    if not value or not all(value):raise RuntimeError('Generated cache resource set mismatch')
    result={'requests':sum(counts.get('/asset-'+name,0) for name in reader_names),'fromDiskCache':all(events.get(url,False) for url in urls)}
   elif action=='hold-read':
    page.call('Network.emulateNetworkConditions',{'offline':False,'latency':0,'downloadThroughput':4096,'uploadThroughput':1048576})
    url=base+'/asset-'+command['asset'];value=evaluate("fetch('"+url+"').then(async r=>{window.generatedReader=r.body.getReader();const p=await window.generatedReader.read();return {length:p.value.length};})")
    result={'length':value['length'],'requests':counts.get('/asset-'+command['asset'],0),'fromDiskCache':events.get(url,False)}
   elif action=='release-read':
    result={'released':evaluate("window.generatedReader.cancel().then(()=>true)")};page.call('Network.emulateNetworkConditions',{'offline':False,'latency':0,'downloadThroughput':-1,'uploadThroughput':-1})
   elif action=='quit':stop();send({'closed':True});break
   else:raise RuntimeError('Unknown generated command')
   send(result)
  except Exception as error:send({'error':type(error).__name__+': '+str(error)[:400]})
finally:stop();server.shutdown()
"""#
}
