//
//  FWDebugDeviceInfo.m
//  FWDebug
//
//  Created by wuyong on 17/2/23.
//  Copyright © 2017年 ocphp.com. All rights reserved.
//

#import "FWDebugSystemInfo.h"

#import <SystemConfiguration/CaptiveNetwork.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>

#include <Endian.h>

#import <sys/types.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>

#import <mach/mach.h>
#import <mach/mach_host.h>
#include <mach/machine.h>

#include <net/if.h>
#include <net/if_dl.h>
#include <ifaddrs.h>
#include <arpa/inet.h>

#define IOS_CELLULAR    @"pdp_ip0"
#define IOS_WIFI        @"en0"
#define IP_ADDR_IPv4    @"ipv4"
#define IP_ADDR_IPv6    @"ipv6"

#define FWDebugStr(str) (str ? [NSString stringWithFormat:@"%@", str] : @"-")
#define FWDebugBool(expr) ((expr) ? @"Yes" : @"No")
#define FWDebugDesc(expr) ((expr != nil) ? [expr description] : @"-")

@interface FWDebugSystemInfo () <UISearchResultsUpdating, UISearchControllerDelegate>

@property (nonatomic, strong) NSMutableArray *systemInfo;

@property (nonatomic, strong) NSMutableArray *tableData;
@property (nonatomic, strong) UISearchController *searchController;

@end

@implementation FWDebugSystemInfo

- (instancetype)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
        self.searchController.searchResultsUpdater = self;
        self.searchController.delegate = self;
        self.searchController.dimsBackgroundDuringPresentation = NO;
        self.tableView.tableHeaderView = self.searchController.searchBar;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.title = @"System Info";
    
    [self initSystemInfo];
    
    self.tableData = self.systemInfo;
}

- (void)initSystemInfo
{
    self.systemInfo = [NSMutableArray array];
    NSMutableArray *rowsData = [NSMutableArray array];
    NSDictionary *sectionData = nil;
    
    //Application
    NSString *applicationName = [[[[NSBundle mainBundle] executablePath] componentsSeparatedByString:@"/"] lastObject];
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *version = [infoDictionary objectForKey:@"CFBundleShortVersionString"];
    NSString *build = [infoDictionary objectForKey:@"CFBundleVersion"];
    
    [rowsData addObjectsFromArray:@[
                                    @{ @"Name" : FWDebugStr(applicationName) },
                                    @{ @"Version" : FWDebugStr(version) },
                                    @{ @"Build" : FWDebugStr(build) },
                                    @{ @"Build Date" : [NSString stringWithFormat:@"%@ - %@", [NSString stringWithUTF8String:__DATE__], [NSString stringWithUTF8String:__TIME__]] },
                                    @{ @"Bundle ID" : [[NSBundle mainBundle] bundleIdentifier] },
                                    @{ @"Debug" : FWDebugBool([self isDebug]) },
                                    @{ @"Badge Number" : [@([UIApplication sharedApplication].applicationIconBadgeNumber) stringValue] },
                                    ]];
    NSArray *urlSchemes = [self urlSchemes];
    if (urlSchemes.count > 1) {
        for (int i = 0; i < urlSchemes.count; i++) {
            [rowsData addObject:@{ @"Url Schemes" : FWDebugStr([urlSchemes objectAtIndex:i]) }];
        }
    } else {
        [rowsData addObject:@{ @"Url Scheme" : FWDebugStr(urlSchemes.count > 0 ? [urlSchemes objectAtIndex:0] : nil) }];
    }
    
    sectionData = @{
                    @"title": @"Application",
                    @"rows": rowsData.copy,
                    };
    [rowsData removeAllObjects];
    [self.systemInfo addObject:sectionData];
    
    //Usage
    sectionData = @{
                    @"title": @"Usage",
                    @"rows": @[
                            @{ @"Memory Size" : [NSByteCountFormatter stringFromByteCount:[self memorySize] countStyle:NSByteCountFormatterCountStyleBinary] },
                            @{ @"Documents Size" : [self sizeOfFolder:[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]] },
                            @{ @"Sandbox Size" : [self sizeOfFolder:NSHomeDirectory()] },
                            ]
                    };
    [self.systemInfo addObject:sectionData];
    
    //System
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];;
    dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm";
    
    sectionData = @{
                    @"title": @"System",
                    @"rows": @[
                            @{ @"System Version" : [NSString stringWithFormat:@"%@ %@", [UIDevice currentDevice].systemName, [UIDevice currentDevice].systemVersion] },
                            @{ @"System Time" : [dateFormatter stringFromDate:[NSDate date]] },
                            @{ @"Boot Time" : [dateFormatter stringFromDate:[self systemBootDate]] },
                            @{ @"Low Power Mode" : FWDebugBool([[NSProcessInfo processInfo] isLowPowerModeEnabled]) }
                            ]
                    };
    [self.systemInfo addObject:sectionData];
    
    //Locale
    NSArray *languages = [NSLocale preferredLanguages];
    for (NSString *language in languages) {
        NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en"];
        NSString *title = languages.count > 1 ? @"User Languages" : @"User Language";
        [rowsData addObject:@{ title : [locale displayNameForKey:NSLocaleIdentifier value:language] }];
    }
    NSString *region = [[NSLocale currentLocale] objectForKey:NSLocaleIdentifier];
    [rowsData addObjectsFromArray:@[
                                    @{ @"Timezone" : [NSTimeZone localTimeZone].name },
                                    @{ @"Region" : [[NSLocale currentLocale] displayNameForKey:NSLocaleIdentifier value:region] },
                                    @{ @"Calendar" : [[[[NSLocale currentLocale] objectForKey:NSLocaleCalendar] calendarIdentifier] capitalizedString] }
                                    ]];
    
    sectionData = @{
                    @"title": @"Locale",
                    @"rows": rowsData.copy
                    };
    [rowsData removeAllObjects];
    [self.systemInfo addObject:sectionData];
    
    //Device
    sectionData = @{
                    @"title": @"Device",
                    @"rows": @[
                            @{ @"Name" : [UIDevice currentDevice].name },
                            @{ @"Model" : self.modelName },
                            @{ @"Identifier" : self.modelIdentifier },
                            @{ @"CPU Count" : [NSString stringWithFormat:@"%lu", (unsigned long)(self.cpuPhysicalCount)] },
                            @{ @"CPU Type" : self.cpuType },
                            @{ @"Architectures" : self.cpuArchitectures },
                            @{ @"Total Memory" : [NSByteCountFormatter stringFromByteCount:self.memoryMarketingSize countStyle:NSByteCountFormatterCountStyleBinary] },
                            @{ @"Available Memory" : [NSByteCountFormatter stringFromByteCount:self.memoryPhysicalSize countStyle:NSByteCountFormatterCountStyleBinary] },
                            @{ @"Capacity" : [NSByteCountFormatter stringFromByteCount:self.diskMarketingSpace countStyle:NSByteCountFormatterCountStyleBinary] },
                            @{ @"Total Capacity" : [NSByteCountFormatter stringFromByteCount:self.diskTotalSpace countStyle:NSByteCountFormatterCountStyleBinary] },
                            @{ @"Free Capacity" : [NSByteCountFormatter stringFromByteCount:self.diskFreeSpace countStyle:NSByteCountFormatterCountStyleBinary] },
                            @{ @"Battery level" : [NSString stringWithFormat:@"%ld%%", (long)([UIDevice currentDevice].batteryLevel * 100)] },
                            @{ @"UUID" : FWDebugStr(self.identifierUUID) },
                            @{ @"Jailbroken" : FWDebugBool(self.isJailbreak) },
                            ]
                    };
    [self.systemInfo addObject:sectionData];
    
    //Local IP Addresses
    NSDictionary* ipInfo = self.localIPAddresses;
    for (NSString* key in ipInfo) {
        [rowsData addObject:@{ [NSString stringWithFormat:@"IP (%@)", key] : ipInfo[key] }];
    }
    
    sectionData = @{
                    @"title": @"Local IP Addresses",
                    @"rows": rowsData.copy
                    };
    [rowsData removeAllObjects];
    [self.systemInfo addObject:sectionData];
    
    //Network
    sectionData = @{
                    @"title": @"Network",
                    @"rows": @[
                            @{ @"MAC Address" : FWDebugDesc(self.macAddress) },
                            @{ @"SSID" : FWDebugDesc(self.SSID) },
                            @{ @"BSSDID" : FWDebugDesc(self.BSSID) },
                            @{ @"Received Wi-Fi" : [NSByteCountFormatter stringFromByteCount:self.receivedWiFi.longLongValue countStyle:NSByteCountFormatterCountStyleBinary] },
                            @{ @"Sent Wi-Fi" : [NSByteCountFormatter stringFromByteCount:self.sentWifi.longLongValue countStyle:NSByteCountFormatterCountStyleBinary] },
                            @{ @"Received Cellular" : [NSByteCountFormatter stringFromByteCount:self.receivedCellular.longLongValue countStyle:NSByteCountFormatterCountStyleBinary] },
                            @{ @"Sent Cellular" : [NSByteCountFormatter stringFromByteCount:self.sentCellular.longLongValue countStyle:NSByteCountFormatterCountStyleBinary] }
                            ]
                    };
    [self.systemInfo addObject:sectionData];
    
    //Cellular
    CTTelephonyNetworkInfo* info = [[CTTelephonyNetworkInfo alloc] init];
    
    sectionData = @{
                    @"title": @"Cellular",
                    @"rows": @[
                            @{ @"Carrier" : self.carrierName },
                            @{ @"Carrier Name" : FWDebugDesc([info.subscriberCellularProvider.carrierName capitalizedString]) },
                            @{ @"Data Connection": FWDebugDesc([info.currentRadioAccessTechnology stringByReplacingOccurrencesOfString:@"CTRadioAccessTechnology" withString:@""]) },
                            @{ @"Country Code" : FWDebugDesc(info.subscriberCellularProvider.mobileCountryCode) },
                            @{ @"Network Code" : FWDebugDesc(info.subscriberCellularProvider.mobileNetworkCode) },
                            @{ @"ISO Country Code" : FWDebugDesc(info.subscriberCellularProvider.isoCountryCode) },
                            @{ @"VoIP Enabled" : FWDebugBool(info.subscriberCellularProvider.allowsVOIP) }
                            ]
                    };
    [self.systemInfo addObject:sectionData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.tableData.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return [[self.tableData objectAtIndex:section] objectForKey:@"title"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSArray *sectionData = [[self.tableData objectAtIndex:section] objectForKey:@"rows"];
    return sectionData.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellIdentifier = @"SystemInfoCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellIdentifier];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:14];
    }
    
    NSArray *sectionData = [[self.tableData objectAtIndex:indexPath.section] objectForKey:@"rows"];
    NSDictionary *cellData = [sectionData objectAtIndex:indexPath.row];
    
    for (NSString *key in cellData) {
        cell.textLabel.text = key;
        cell.detailTextLabel.text = [cellData objectForKey:key];
        break;
    }
    
    return cell;
}

#pragma mark - UISearchController

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    if (!self.searchController.isActive) {
        self.tableData = self.systemInfo;
        [self.tableView reloadData];
        return;
    }
    
    //Search Rows
    NSMutableArray *sectionRows = [NSMutableArray array];
    NSString *searchKey = self.searchController.searchBar.text;
    if (searchKey.length > 0) {
        for (NSDictionary *sectionData in self.systemInfo) {
            NSArray *cellDatas = [sectionData objectForKey:@"rows"];
            for (NSDictionary *cellData in cellDatas) {
                for (NSString *cellKey in cellData) {
                    if ([cellKey rangeOfString:searchKey].location != NSNotFound ||
                        [[cellData objectForKey:cellKey] rangeOfString:searchKey].location != NSNotFound) {
                        [sectionRows addObject:cellData];
                    }
                    break;
                }
            }
        }
    }
    
    //Show Results
    self.tableData = [NSMutableArray array];
    NSDictionary *sectionData = @{
                                  @"title": [NSString stringWithFormat:@"%@ Results", @(sectionRows.count)],
                                  @"rows": sectionRows,
                                  };
    [self.tableData addObject:sectionData];
    [self.tableView reloadData];
}

- (void)willDismissSearchController:(UISearchController *)searchController
{
    self.tableData = self.systemInfo;
    [self.tableView reloadData];
}

#pragma mark - Private

- (NSString *)sizeOfFolder:(NSString *)folderPath
{
    NSArray *contents = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:folderPath error:nil];
    NSEnumerator *contentsEnumurator = [contents objectEnumerator];
    
    NSString *file;
    unsigned long long int folderSize = 0;
    
    while (file = [contentsEnumurator nextObject]) {
        NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[folderPath stringByAppendingPathComponent:file] error:nil];
        folderSize += [[fileAttributes objectForKey:NSFileSize] intValue];
    }
    
    NSString *folderSizeStr = [NSByteCountFormatter stringFromByteCount:folderSize countStyle:NSByteCountFormatterCountStyleFile];
    return folderSizeStr;
}

- (long long)memorySize
{
    struct task_basic_info info;
    mach_msg_type_number_t size = sizeof(info);
    kern_return_t kerr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &size);
    
    if (kerr == KERN_SUCCESS) {
        return (long long)info.resident_size;
    } else {
        return -1;
    }
}

- (NSDate *)systemBootDate
{
    const int MIB_SIZE = 2;
    
    int mib[MIB_SIZE];
    size_t size;
    struct timeval  boottime;
    
    mib[0] = CTL_KERN;
    mib[1] = KERN_BOOTTIME;
    size = sizeof(boottime);
    
    if (sysctl(mib, MIB_SIZE, &boottime, &size, NULL, 0) != -1) {
        NSDate* bootDate = [NSDate dateWithTimeIntervalSince1970:boottime.tv_sec + boottime.tv_usec / 1.e6];
        return bootDate;
    }
    
    return nil;
}

#pragma mark - CPU related

- (NSUInteger)cpuCount
{
    return (NSUInteger)[[self systemInfoByName:@"hw.ncpu"] integerValue];
}

- (NSUInteger)cpuActiveCount
{
    return (NSUInteger)[[self systemInfoByName:@"hw.activecpu"] integerValue];
}

- (NSUInteger)cpuPhysicalCount
{
    return (NSUInteger)[[self systemInfoByName:@"hw.physicalcpu"] integerValue];
}

- (NSUInteger)cpuPhysicalMaximumCount
{
    return (NSUInteger)[[self systemInfoByName:@"hw.physicalcpu_max"] integerValue];
}

- (NSUInteger)cpuLogicalCount
{
    return (NSUInteger)[[self systemInfoByName:@"hw.logicalcpu"] integerValue];
}

- (NSUInteger)cpuLogicalMaximumCount
{
    return (NSUInteger)[[self systemInfoByName:@"hw.logicalcpu_max"] integerValue];
}

- (NSUInteger)cpuFrequency
{
    return (NSUInteger)[[self systemInfoByName:@"hw.cpufrequency"] integerValue];
}

- (NSUInteger)cpuMaximumFrequency
{
    return (NSUInteger)[[self systemInfoByName:@"hw.cpufrequency_max"] integerValue];
}

- (NSUInteger)cpuMinimumFrequency
{
    return (NSUInteger)[[self systemInfoByName:@"hw.cpufrequency_min"] integerValue];
}

- (NSString *)cpuType
{
    NSString *cpuType = [self systemInfoByName:@"hw.cputype"];
    
    switch (cpuType.integerValue) {
        case 1:
            return @"VAC";
        case 6:
            return @"MC680x0";
        case 7:
            return @"x86";
        case 10:
            return @"MC88000";
        case 11:
            return @"HPPA";
        case 12:
        case 16777228:
            return @"arm";
        case 13:
            return @"MC88000";
        case 14:
            return @"Sparc";
        case 15:
            return @"i860";
        case 18:
            return @"PowerPC";
        default:
            return @"Any";
    }
}

- (NSString *)cpuSubType
{
    return [self systemInfoByName:@"hw.cpusubtype"];
}

- (NSString *)cpuArchitectures
{
    NSMutableArray *architectures = [NSMutableArray array];
    
    NSInteger type = [self systemInfoByName:@"hw.cputype"].integerValue;
    NSInteger subtype = [self systemInfoByName:@"hw.cpusubtype"].integerValue;
    
    if (type == CPU_TYPE_X86)
    {
        [architectures addObject:@"x86"];
        
        if (subtype == CPU_SUBTYPE_X86_64_ALL || subtype == CPU_SUBTYPE_X86_64_H)
        {
            [architectures addObject:@"x86_64"];
        }
    }
    else
    {
        if (subtype == CPU_SUBTYPE_ARM_V6)
        {
            [architectures addObject:@"armv6"];
        }
        
        if (subtype == CPU_SUBTYPE_ARM_V7)
        {
            [architectures addObject:@"armv7"];
        }
        
        if (subtype == CPU_SUBTYPE_ARM_V7S)
        {
            [architectures addObject:@"armv7s"];
        }
        
        if (subtype == CPU_SUBTYPE_ARM64_V8)
        {
            [architectures addObject:@"arm64"];
        }
    }
    
    return [architectures componentsJoinedByString:@", "];
}


#pragma mark - Memory Related

- (unsigned long long)memoryMarketingSize
{
    unsigned long long totalSpace = [self memoryPhysicalSize];
    
    double next = pow(2, ceil (log (totalSpace) / log(2)));
    
    return (unsigned long long)next;
    
}

- (unsigned long long)memoryPhysicalSize
{
    return (unsigned long long)[[self systemInfoByName:@"hw.memsize"] longLongValue];
}

#pragma mark - Disk Space Related

- (unsigned long long)diskMarketingSpace
{
    unsigned long long totalSpace = [self diskTotalSpace];
    
    double next = pow(2, ceil (log (totalSpace) / log(2)));
    
    return (unsigned long long)next;
}

- (unsigned long long)diskTotalSpace
{
    NSDictionary *fattributes = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:nil];
    return [[fattributes objectForKey:NSFileSystemSize] unsignedLongLongValue];
}

- (unsigned long long)diskFreeSpace
{
    NSDictionary *fattributes = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:nil];
    return [[fattributes objectForKey:NSFileSystemFreeSize] unsignedLongLongValue];
}

#pragma mark - Device Info

- (NSArray<NSString *> *)urlSchemes
{
    NSMutableArray *urlSchemes = [NSMutableArray array];
    NSArray *array = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleURLTypes"];
    for ( NSDictionary *dict in array ) {
        NSArray *dictSchemes = [dict objectForKey:@"CFBundleURLSchemes"];
        NSString *urlScheme = dictSchemes.count > 0 ? [dictSchemes objectAtIndex:0] : nil;
        if ( urlScheme && urlScheme.length ) {
            [urlSchemes addObject:urlScheme];
        }
    }
    return urlSchemes;
}

- (NSString *)identifierUUID
{
    return [[[UIDevice currentDevice] identifierForVendor] UUIDString];
}

- (BOOL)isDebug
{
    BOOL isDebug = NO;
#ifdef DEBUG
#if DEBUG
    isDebug = YES;
#endif
#endif
    return isDebug;
}

- (BOOL)isJailbreak
{
#if TARGET_OS_SIMULATOR
    return NO;
#else
    // 1
    NSArray *paths = @[@"/Applications/Cydia.app",
                       @"/private/var/lib/apt/",
                       @"/private/var/lib/cydia",
                       @"/private/var/stash"];
    for (NSString *path in paths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return YES;
        }
    }
    
    // 2
    FILE *bash = fopen("/bin/bash", "r");
    if (bash != NULL) {
        fclose(bash);
        return YES;
    }
    
    // 3
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    CFStringRef string = CFUUIDCreateString(NULL, uuid);
    CFRelease(uuid);
    NSString *uuidString = (__bridge_transfer NSString *)string;
    NSString *path = [NSString stringWithFormat:@"/private/%@", uuidString];
    if ([@"test" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return YES;
    }
    
    return NO;
#endif
}

- (NSString *)systemInfoByName:(NSString *)name
{
    const char* typeSpecifier = [name cStringUsingEncoding:NSASCIIStringEncoding];
    
    size_t size;
    sysctlbyname(typeSpecifier, NULL, &size, NULL, 0);
    
    NSString *results = nil;
    
    if (size == 4)
    {
        uint32_t *answer = malloc(size);
        sysctlbyname(typeSpecifier, answer, &size, NULL, 0);
        
        uint32_t final = EndianU32_NtoL(*answer);
        
        results = [NSString stringWithFormat:@"%d", final];
        
        free(answer);
    }
    else if (size == 8)
    {
        long long *answer = malloc(size);
        sysctlbyname(typeSpecifier, answer, &size, NULL, 0);
        
        results = [NSString stringWithFormat:@"%lld", *answer];
        
        free(answer);
    }
    else if (size == 0)
    {
        results = @"0";
    }
    else
    {
        char *answer = malloc(size);
        sysctlbyname(typeSpecifier, answer, &size, NULL, 0);
        
        results = [NSString stringWithCString:answer encoding:NSUTF8StringEncoding];
        
        free(answer);
    }
    
    return results;
}

- (NSString *)modelIdentifier
{
    return [self systemInfoByName:@"hw.machine"];
}

- (NSString *)modelName
{
    return [self modelNameForModelIdentifier:[self modelIdentifier]];
}

- (NSString *)modelNameForModelIdentifier:(NSString *)modelIdentifier
{
    NSDictionary *dic = @{
                          @"Watch1,1" : @"Apple Watch 38mm",
                          @"Watch1,2" : @"Apple Watch 42mm",
                          @"Watch2,3" : @"Apple Watch Series 2 38mm",
                          @"Watch2,4" : @"Apple Watch Series 2 42mm",
                          @"Watch2,6" : @"Apple Watch Series 1 38mm",
                          @"Watch1,7" : @"Apple Watch Series 1 42mm",
                          
                          @"iPod1,1" : @"iPod touch 1",
                          @"iPod2,1" : @"iPod touch 2",
                          @"iPod3,1" : @"iPod touch 3",
                          @"iPod4,1" : @"iPod touch 4",
                          @"iPod5,1" : @"iPod touch 5",
                          @"iPod7,1" : @"iPod touch 6",
                          
                          @"iPhone1,1" : @"iPhone 1G",
                          @"iPhone1,2" : @"iPhone 3G",
                          @"iPhone2,1" : @"iPhone 3GS",
                          @"iPhone3,1" : @"iPhone 4 (GSM)",
                          @"iPhone3,2" : @"iPhone 4",
                          @"iPhone3,3" : @"iPhone 4 (CDMA)",
                          @"iPhone4,1" : @"iPhone 4S",
                          @"iPhone5,1" : @"iPhone 5",
                          @"iPhone5,2" : @"iPhone 5",
                          @"iPhone5,3" : @"iPhone 5c",
                          @"iPhone5,4" : @"iPhone 5c",
                          @"iPhone6,1" : @"iPhone 5s",
                          @"iPhone6,2" : @"iPhone 5s",
                          @"iPhone7,1" : @"iPhone 6 Plus",
                          @"iPhone7,2" : @"iPhone 6",
                          @"iPhone8,1" : @"iPhone 6s",
                          @"iPhone8,2" : @"iPhone 6s Plus",
                          @"iPhone8,4" : @"iPhone SE",
                          @"iPhone9,1" : @"iPhone 7",
                          @"iPhone9,2" : @"iPhone 7 Plus",
                          @"iPhone9,3" : @"iPhone 7",
                          @"iPhone9,4" : @"iPhone 7 Plus",
                          
                          @"iPad1,1" : @"iPad 1",
                          @"iPad2,1" : @"iPad 2 (WiFi)",
                          @"iPad2,2" : @"iPad 2 (GSM)",
                          @"iPad2,3" : @"iPad 2 (CDMA)",
                          @"iPad2,4" : @"iPad 2",
                          @"iPad2,5" : @"iPad mini 1",
                          @"iPad2,6" : @"iPad mini 1",
                          @"iPad2,7" : @"iPad mini 1",
                          @"iPad3,1" : @"iPad 3 (WiFi)",
                          @"iPad3,2" : @"iPad 3 (4G)",
                          @"iPad3,3" : @"iPad 3 (4G)",
                          @"iPad3,4" : @"iPad 4",
                          @"iPad3,5" : @"iPad 4",
                          @"iPad3,6" : @"iPad 4",
                          @"iPad4,1" : @"iPad Air",
                          @"iPad4,2" : @"iPad Air",
                          @"iPad4,3" : @"iPad Air",
                          @"iPad4,4" : @"iPad mini 2",
                          @"iPad4,5" : @"iPad mini 2",
                          @"iPad4,6" : @"iPad mini 2",
                          @"iPad4,7" : @"iPad mini 3",
                          @"iPad4,8" : @"iPad mini 3",
                          @"iPad4,9" : @"iPad mini 3",
                          @"iPad5,1" : @"iPad mini 4",
                          @"iPad5,2" : @"iPad mini 4",
                          @"iPad5,3" : @"iPad Air 2",
                          @"iPad5,4" : @"iPad Air 2",
                          @"iPad6,3" : @"iPad Pro (9.7 inch)",
                          @"iPad6,4" : @"iPad Pro (9.7 inch)",
                          @"iPad6,7" : @"iPad Pro (12.9 inch)",
                          @"iPad6,8" : @"iPad Pro (12.9 inch)",
                          
                          @"AppleTV2,1" : @"Apple TV 2",
                          @"AppleTV3,1" : @"Apple TV 3",
                          @"AppleTV3,2" : @"Apple TV 3",
                          @"AppleTV5,3" : @"Apple TV 4",
                          
                          @"i386" : @"Simulator x86",
                          @"x86_64" : @"Simulator x64",
                          };
    
    NSString *modelName = [dic objectForKey:modelIdentifier];
    return modelName ? modelName : modelIdentifier;
}

#pragma mark - Network

- (NSString *)SSID
{
    return [self fetchSSID][@"SSID"];
}

- (NSString *)BSSID
{
    return [self fetchSSID][@"BSSID"];
}

- (NSString *)macAddress
{
    int mib[6];
    size_t len;
    char *buf;
    unsigned char *ptr;
    struct if_msghdr *ifm;
    struct sockaddr_dl *sdl;
    
    mib[0] = CTL_NET;
    mib[1] = AF_ROUTE;
    mib[2] = 0;
    mib[3] = AF_LINK;
    mib[4] = NET_RT_IFLIST;
    
    if ((mib[5] = if_nametoindex("en0")) == 0)
    {
        printf("Error: if_nametoindex error\n");
        return NULL;
    }
    
    if (sysctl(mib, 6, NULL, &len, NULL, 0) < 0)
    {
        printf("Error: sysctl, take 1\n");
        return NULL;
    }
    
    if ((buf = malloc(len)) == NULL)
    {
        printf("Could not allocate memory. error!\n");
        return NULL;
    }
    
    if (sysctl(mib, 6, buf, &len, NULL, 0) < 0)
    {
        printf("Error: sysctl, take 2");
        return NULL;
    }
    
    ifm = (struct if_msghdr *)buf;
    sdl = (struct sockaddr_dl *)(ifm + 1);
    ptr = (unsigned char *)LLADDR(sdl);
    NSString *outstring = [NSString stringWithFormat:@"%02X:%02X:%02X:%02X:%02X:%02X", *ptr, *(ptr + 1), *(ptr + 2), *(ptr + 3), *(ptr + 4), *(ptr + 5)];
    
    free(buf);
    
    return outstring;
}

- (NSDictionary *)localIPAddresses
{
    NSMutableDictionary *localInterfaces = [NSMutableDictionary dictionary];
    
    // retrieve the current interfaces - returns 0 on success
    struct ifaddrs *interfaces;
    
    if (!getifaddrs(&interfaces))
    {
        // Loop through linked list of interfaces
        struct ifaddrs *interface;
        for (interface = interfaces; interface; interface=interface->ifa_next)
        {
            if (!(interface->ifa_flags & IFF_UP) || (interface->ifa_flags & IFF_LOOPBACK))
            {
                continue; // deeply nested code harder to read
            }
            
            const struct sockaddr_in *addr = (const struct sockaddr_in*)interface->ifa_addr;
            if(addr && (addr->sin_family == AF_INET || addr->sin_family == AF_INET6))
            {
                NSString *name = [NSString stringWithUTF8String:interface->ifa_name];
                char addrBuf[INET6_ADDRSTRLEN];
                if (inet_ntop(addr->sin_family, &addr->sin_addr, addrBuf, sizeof(addrBuf)))
                {
                    
                    NSString *key = [NSString stringWithFormat:@"%@/%@", name, addr->sin_family == AF_INET ? IP_ADDR_IPv4 : IP_ADDR_IPv6];
                    
                    localInterfaces[key] = [NSString stringWithUTF8String:addrBuf];
                }
            }
        }
        // Free memory
        freeifaddrs(interfaces);
    }
    return [localInterfaces copy];
}

- (NSNumber *)receivedWiFi
{
    return [[self networkDataCounters] objectAtIndex:1];
}

- (NSNumber *)receivedCellular
{
    return [[self networkDataCounters] objectAtIndex:3];
}

- (NSNumber *)sentWifi
{
    return [[self networkDataCounters] objectAtIndex:0];
}

- (NSNumber *)sentCellular
{
    return [[self networkDataCounters] objectAtIndex:2];
}

#pragma mark - Private methods

- (NSDictionary *)fetchSSID
{
    NSArray *ifs = (__bridge_transfer id)CNCopySupportedInterfaces();
    
    id info = nil;
    
    for (NSString *ifnam in ifs) {
        
        info = (__bridge_transfer id)CNCopyCurrentNetworkInfo((__bridge CFStringRef)ifnam);
        
        //  CLS_LOG(@"%@ => %@", ifnam, info);
        
        if (info && [info count]) {
            break;
        }
    }
    
    return info;
}

- (NSArray *)networkDataCounters
{
    BOOL success;
    struct ifaddrs *addrs;
    const struct ifaddrs *cursor;
    const struct if_data *networkStatistics;
    
    u_int64_t WiFiSent = 0;
    u_int64_t WiFiReceived = 0;
    u_int64_t WWANSent = 0;
    u_int64_t WWANReceived = 0;
    
    NSString *name = nil;
    
    success = getifaddrs(&addrs) == 0;
    
    if (success)
    {
        cursor = addrs;
        
        while (cursor != NULL)
        {
            name = [NSString stringWithFormat:@"%s", cursor->ifa_name];
            
            if (cursor->ifa_addr->sa_family == AF_LINK)
            {
                if ([name hasPrefix:@"en"])
                {
                    networkStatistics = (const struct if_data *) cursor->ifa_data;
                    WiFiSent += networkStatistics->ifi_obytes;
                    WiFiReceived += networkStatistics->ifi_ibytes;
                }
                
                if ([name hasPrefix:@"pdp_ip"])
                {
                    networkStatistics = (const struct if_data *) cursor->ifa_data;
                    WWANSent += networkStatistics->ifi_obytes;
                    WWANReceived += networkStatistics->ifi_ibytes;
                }
            }
            
            cursor = cursor->ifa_next;
        }
        
        freeifaddrs(addrs);
    }
    
    return @[ @(WiFiSent), @(WiFiReceived), @(WWANSent), @(WWANReceived) ];
}

- (NSString *)carrierName
{
    NSString *statusBarString = [NSString stringWithFormat:@"%@ar", @"_statusB"];
    UIView* statusBar = [[UIApplication sharedApplication] valueForKey:statusBarString];
    
    UIView* statusBarForegroundView = nil;
    
    for (UIView* view in statusBar.subviews)
    {
        if ([view isKindOfClass:NSClassFromString(@"UIStatusBarForegroundView")])
        {
            statusBarForegroundView = view;
            break;
        }
    }
    
    UIView* statusBarServiceItem = nil;
    
    for (UIView* view in statusBarForegroundView.subviews)
    {
        if ([view isKindOfClass:NSClassFromString(@"UIStatusBarServiceItemView")])
        {
            statusBarServiceItem = view;
            break;
        }
    }
    
    if (statusBarServiceItem)
    {
        id value = [statusBarServiceItem valueForKey:@"_serviceString"];
        
        if ([value isKindOfClass:[NSString class]])
        {
            return (NSString *)value;
        }
    }
    
    return @"Unavailable";
}

@end