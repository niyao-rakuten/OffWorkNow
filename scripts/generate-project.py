#!/usr/bin/env python3
"""Generate the dependency-free native Xcode project. Run after adding sources."""
from pathlib import Path
import hashlib
import html
root = Path(__file__).resolve().parent.parent
project = root / 'XiaBanLa.xcodeproj'
(project / 'xcshareddata/xcschemes').mkdir(parents=True, exist_ok=True)
def ID(key): return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
objects = []
def obj(key, body): objects.append(f'{ID(key)} = {{ {body} }};'); return ID(key)
def arr(keys): return '(' + ', '.join(ID(k) for k in keys) + ',)'
folders = {'app': 'Sources/WorkdayBuddy', 'ios': 'Sources/XiaBanLaIOS', 'shared': 'Sources/SharedUI', 'tests': 'Tests/WorkdayCoreTests'}
files = {}
for folder, path in folders.items():
 files[folder] = []
 for file in sorted((root / path).glob('*.swift')):
  key = f'{folder}/{file.name}'; files[folder].append(key)
  obj(key, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file.name}; sourceTree = "<group>";')
 obj(folder, f'isa = PBXGroup; children = {arr(files[folder])}; path = {path}; sourceTree = "<group>";')
obj('assets', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Resources/Assets.xcassets; sourceTree = "<group>";')
obj('petart', 'isa = PBXFileReference; lastKnownFileType = folder; path = Resources/PetArt; sourceTree = \"<group>\";')
obj('privacy', 'isa = PBXFileReference; lastKnownFileType = text.xml; path = Configuration/PrivacyInfo.xcprivacy; sourceTree = "<group>";')
for key, path in [('plist', 'Info.plist'), ('iosplist','Info-iOS.plist'), ('entitlements','XiaBanLa.entitlements')]:
 obj(key, f'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = {path}; sourceTree = "<group>";')
obj('configuration', f'isa = PBXGroup; children = {arr(["plist","iosplist","entitlements"])}; path = Configuration; sourceTree = "<group>";')
obj('localPackage','isa = XCLocalSwiftPackageReference; relativePath = .;')
products = []
for target, name in [('app','XiaBanLa'), ('ios','XiaBanLa-iOS'), ('test','WorkdayCoreTests')]:
 product = '下班啦.app' if target != 'test' else 'WorkdayCoreTests.xctest'
 obj(target+'Product',f'isa = PBXFileReference; explicitFileType = '+('wrapper.application' if target != 'test' else 'wrapper.cfbundle')+f'; path = "{product}"; sourceTree = BUILT_PRODUCTS_DIR;')
 products.append(target+'Product')
 obj(target+'core',f'isa = XCSwiftPackageProductDependency; package = {ID("localPackage")}; productName = WorkdayCore;')
 obj(target+'coreBuild',f'isa = PBXBuildFile; productRef = {ID(target+"core")};')
 obj(target+'frameworks',f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {arr([target+"coreBuild"])}; runOnlyForDeploymentPostprocessing = 0;')
 sourcefiles = files['tests'] if target == 'test' else files['app' if target == 'app' else 'ios'] + files['shared']
 builds = []
 for file in sourcefiles:
  key = target+'build'+file; obj(key, f'isa = PBXBuildFile; fileRef = {ID(file)};'); builds.append(key)
 obj(target+'sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(builds)}; runOnlyForDeploymentPostprocessing = 0;')
 phases = [target+'sources',target+'frameworks']
 if target != 'test':
  for key in ['assets','privacy','petart']: obj(target+key+'build',f'isa = PBXBuildFile; fileRef = {ID(key)};')
  obj(target+'resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {arr([target+"assetsbuild",target+"privacybuild",target+"petartbuild"])}; runOnlyForDeploymentPostprocessing = 0;'); phases.append(target+'resources')
 for config in ['Debug','Release']:
  settings = 'SWIFT_VERSION = 5.0; CODE_SIGN_STYLE = Automatic;'
  if target == 'ios':
   settings += ' SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 16.0; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; TARGETED_DEVICE_FAMILY = "1,2"; PRODUCT_MODULE_NAME = XiaBanLaIOS; INFOPLIST_FILE = Configuration/Info-iOS.plist; SUPPORTS_MACCATALYST = NO;'
  else:
   settings += ' SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 13.0; ARCHS = "$(NATIVE_ARCH_ACTUAL)"; ONLY_ACTIVE_ARCH = YES;'
   if target == 'app': settings += ' PRODUCT_MODULE_NAME = WorkdayBuddy; INFOPLIST_FILE = Configuration/Info.plist; CODE_SIGN_ENTITLEMENTS = Configuration/XiaBanLa.entitlements; ENABLE_APP_SANDBOX = YES; ENABLE_HARDENED_RUNTIME = YES; COMBINE_HIDPI_IMAGES = YES;'
  if target == 'test': settings += ' PRODUCT_NAME = WorkdayCoreTests; PRODUCT_BUNDLE_IDENTIFIER = com.workdaybuddy.tests; GENERATE_INFOPLIST_FILE = YES; CODE_SIGN_IDENTITY = "-";'
  else:
   settings += ' PRODUCT_NAME = "下班啦"; PRODUCT_BUNDLE_IDENTIFIER = com.workdaybuddy.app; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; CURRENT_PROJECT_VERSION = 2; MARKETING_VERSION = 1.1.0; SKIP_INSTALL = NO;'
   if config == 'Debug' and target == 'app': settings += ' CODE_SIGN_IDENTITY = "-";'
  obj(target+config,f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ {settings} }};')
 obj(target+'config',f'isa = XCConfigurationList; buildConfigurations = {arr([target+"Debug",target+"Release"])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
 obj(target+'target',f'isa = PBXNativeTarget; name = "{name}"; buildConfigurationList = {ID(target+"config")}; buildPhases = {arr(phases)}; buildRules = (); dependencies = (); packageProductDependencies = {arr([target+"core"])}; productReference = {ID(target+"Product")}; productType = "'+('com.apple.product-type.bundle.unit-test' if target=='test' else 'com.apple.product-type.application')+'";')
obj('products',f'isa = PBXGroup; children = {arr(products)}; name = Products; sourceTree = "<group>";')
obj('root',f'isa = PBXGroup; children = {arr([*folders,"configuration","assets","privacy","petart","products"])}; sourceTree = "<group>";')
for config in ['Debug','Release']:
 settings = 'CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 5.0;'
 settings += ' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; ENABLE_TESTABILITY = YES; DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if config=='Debug' else ' SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
 obj('project'+config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ {settings} }};')
obj('projectconfig',f'isa = XCConfigurationList; buildConfigurations = {arr(["projectDebug","projectRelease"])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2600; }}; buildConfigurationList = {ID("projectconfig")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh_CN; hasScannedForEncodings = 0; knownRegions = (zh_CN, en, Base); mainGroup = {ID("root")}; productRefGroup = {ID("products")}; projectDirPath = ""; projectRoot = ""; packageReferences = {arr(["localPackage"])}; targets = {arr(["apptarget","iostarget","testtarget"])};')
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {ID("project")}; }}\n')
def ref(target, name, product): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ID(target+"target")}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:XiaBanLa.xcodeproj"/>'
for target,name in [('app','XiaBanLa'),('ios','XiaBanLa-iOS')]:
 r = ref(target,name,'下班啦.app')
 test = '<Testables><TestableReference skipped="NO">'+ref('test','WorkdayCoreTests','WorkdayCoreTests.xctest')+'</TestableReference></Testables>' if target=='app' else '<Testables/>'
 scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{r}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">{test}</TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{r}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{r}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
 (project/'xcshareddata/xcschemes'/f'{name}.xcscheme').write_text(scheme)
