// The MIT License (MIT)
//
// Copyright (c) 2017 - present zqqf16
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.


#import "MDDeviceFile.h"
#import "MDAfcClient.h"

@interface MDDeviceFile ()
@property (nonatomic, strong) MDAfcClient *afcClient;
@property (nonatomic, readwrite) NSArray<MDDeviceFile *> *children;
@end

@implementation MDDeviceFile

- (instancetype)initWithAfcClient:(MDAfcClient *)afcClient {
    if (self = [super init]) {
        _afcClient = afcClient;
    }
    
    return self;
}

- (NSString *)name {
    return [self.path lastPathComponent];
}

- (NSString *)lowercaseName {
    return self.name.lowercaseString;
}

- (NSString *)extension {
    return [self.path pathExtension];
}

- (NSString *)description {
    return self.path;
}

- (NSArray *)children {
    if (!self.isDirectory) {
        return nil;
    }

    if (_children) {
        return _children;
    }
    
    _children = [self.afcClient listDirectory:self.path];
    return _children;
}

- (NSData *)read {
    if (!self.afcClient) {
        return nil;
    }
    
    return [self.afcClient read:self.path];
}

- (void)copy:(NSString *)path {
    if (!self.isDirectory) {
        NSData *data = [self read];
        if (!data) {
            return;
        }

        [data writeToFile:path atomically:YES];
        return;
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory;
    if (![fileManager fileExistsAtPath:path isDirectory:&isDirectory]) {
        NSError *error;
        [fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            NSLog(@"ERROR: create directory failed: %@", error);
            return;
        }
    } else if (!isDirectory) {
        NSLog(@"ERROR: create directory failed: %@ existed", path);
        return;
    }

    NSArray *children = self.children;
    if (children.count == 0) {
        return;
    }
    for (MDDeviceFile *file in self.children) {
        NSString *filePath = [path stringByAppendingPathComponent:file.name];
        [file copy:filePath];
    }
}

- (BOOL)uploadFromLocalPath:(NSString *)localPath {
    if (!self.afcClient) {
        return NO;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory;
    if (![fileManager fileExistsAtPath:localPath isDirectory:&isDirectory]) {
        return NO;
    }

    NSString *fileName = [localPath lastPathComponent];
    NSString *remotePath;
    if ([self.path isEqualToString:@"."]) {
        remotePath = fileName;
    } else {
        remotePath = [self.path stringByAppendingPathComponent:fileName];
    }

    if (!isDirectory) {
        NSData *data = [NSData dataWithContentsOfFile:localPath];
        if (!data) {
            NSLog(@"ERROR: Unable to read local file '%@'", localPath);
            return NO;
        }
        return [self.afcClient write:remotePath data:data];
    }

    if (![self.afcClient makeDirectory:remotePath]) {
        NSLog(@"ERROR: Unable to create directory '%@' on device", remotePath);
        return NO;
    }

    NSArray *contents = [fileManager contentsOfDirectoryAtPath:localPath error:nil];
    for (NSString *item in contents) {
        NSString *localItemPath = [localPath stringByAppendingPathComponent:item];
        MDDeviceFile *remoteDir = [[MDDeviceFile alloc] initWithAfcClient:self.afcClient];
        remoteDir.path = remotePath;
        remoteDir.isDirectory = YES;
        if (![remoteDir uploadFromLocalPath:localItemPath]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)remove {
    if (!self.afcClient) {
        return NO;
    }
    
    if (self.isDirectory) {
        for (MDDeviceFile *file in self.children) {
            if (![file remove]) {
                return NO;
            }
        }
        self.children = @[];
    }
    
    return [self.afcClient remove:self.path];
}

- (BOOL)removeChild:(MDDeviceFile *)child {
    if ([self.children containsObject:child]) {
        if ([child remove]) {
            NSMutableArray *tmpChildren = [self.children mutableCopy];
            [tmpChildren removeObject:child];
            self.children = [tmpChildren copy];
            return YES;
        }
    }
    return NO;
}

@end
