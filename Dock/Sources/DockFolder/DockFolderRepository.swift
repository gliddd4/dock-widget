//
//  DockFolderRepository.swift
//  Pock
//
//  Created by Pierluigi Galdi on 05/05/2019.
//  Copyright © 2019 Pierluigi Galdi. All rights reserved.
//

import Foundation
import PockKit

class DockFolderRepository {
    
    deinit {
        NSLog("[DockWidget][MEM] DockFolderRepository deinit. RSS: %d MB", pockMemoryFootprintMB())
    }
    
    private weak var rootFolderController: DockFolderController?
    
    private var navigationController: PKTouchBarNavigationController? {
        return rootFolderController?.mainNavigationController
    }
    
    public var shouldShowBackButton: Bool {
        return navigationController?.childControllers.count ?? 0 > 2
    }
    
    func getItems(in path: URL, _ completion: (([DockFolderItem]) -> Void)?) {
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey,
                                                      .isApplicationKey,
                                                      .effectiveIconKey,
                                                      .nameKey,
                                                      .localizedTypeDescriptionKey]
        DispatchQueue.global(qos: .background).async {
            var returnable: [DockFolderItem] = []
            let enumerator = FileManager.default.enumerator(at: path,
                                                            includingPropertiesForKeys: resourceKeys,
                                                            options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants, .skipsHiddenFiles],
                                                            errorHandler: nil)
            while let elementUrl = enumerator?.nextObject() as? URL {
                guard let itemData = try? elementUrl.resourceValues(forKeys: Set(resourceKeys)).allValues else {
                    continue
                }
                let icon          = itemData[.effectiveIconKey] as? NSImage ?? DockRepository.getIcon(orPath: elementUrl.path)
                let name          = itemData[.nameKey]                     as? String
                let detail        = itemData[.localizedTypeDescriptionKey] as? String
                let isDirectory   = itemData[.isDirectoryKey]              as? Bool
                let isApplication = itemData[.isApplicationKey]            as? Bool
                let item = DockFolderItem(0, name: name, detail: detail, path: elementUrl, icon: icon, isDirectory: isDirectory, isApplication: isApplication)
                returnable.append(item)
            }
            returnable.sort(by: { $0.name ?? "" < $1.name ?? "" })
            DispatchQueue.main.async {
                NSLog("[DockWidget][MEM] Folder scan done: %d items for %@. RSS: %d MB", returnable.count, path.lastPathComponent, pockMemoryFootprintMB())
                completion?(returnable)
            }
        }
    }
    
    func open(item: DockFolderItem, completion: ((Bool) -> Void)? = nil) {
        var completed: Bool     = false
        var shouldDismiss: Bool = true
        if item.isApplication {
            let app = try? NSWorkspace.shared.launchApplication(at: item.path!, options: [NSWorkspace.LaunchOptions.default], configuration: [:])
            completed = app != nil
            
        }else if item.isDirectory {
            push(item.path!)
            completed     = true
            shouldDismiss = false
            
        }else {
            completed = NSWorkspace.shared.open(item.path!)
        }
        if shouldDismiss {
            popToRootDockFolderController()
        }
        completion?(completed)
    }
    
}

extension DockFolderRepository {
    public func push(_ path: URL) {
        NSLog("[DockWidget][MEM] push folder: %@ (RSS: %d MB, nav stack: %d)", path.lastPathComponent, pockMemoryFootprintMB(), navigationController?.childControllers.count ?? -1)
        let controller: DockFolderController = DockFolderController.load()
        controller.set(dockFolderRepository: self)
        controller.set(folderUrl: path)
        if rootFolderController == nil {
            rootFolderController = controller
            controller.pushOnMainNavigationController()
        }else {
            navigationController?.push(controller)
        }
    }
    public func popDockFolderController() {
        navigationController?.popLastController()
        NSLog("[DockWidget][MEM] popped folder controller. RSS: %d MB, nav stack: %d", pockMemoryFootprintMB(), navigationController?.childControllers.count ?? -1)
    }
    public func popToRootDockFolderController() {
        navigationController?.popToRootController()
        NSLog("[DockWidget][MEM] popped to root folder controller. RSS: %d MB, nav stack: %d", pockMemoryFootprintMB(), navigationController?.childControllers.count ?? -1)
    }
}

