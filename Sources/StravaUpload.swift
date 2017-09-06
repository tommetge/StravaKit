//
//  StravaUpload.swift
//  StravaKit
//
//  Created by Brennan Stehling on 8/22/16.
//  Copyright © 2016 SmallSharpTools LLC. All rights reserved.
//

import Foundation

public enum UploadResourcePath: String {
    case Upload = "/api/v3/uploads"
    case CheckUpload = "/api/v3/uploads/:id"
}

public extension Strava {

    /**
     Uploads an activity for current athlete.

     ```swift
     Strava.uploadActivity(fileURL) { (activity, error) in }
     ```

     Docs: https://strava.github.io/api/v3/uploads/#post-file
     */

    @discardableResult
    public static func uploadActivity(_ activityFileURL: URL, type: String? = nil, name: String? = nil, description: String? = nil, completionHandler:((_ status: Bool, _ error: NSError?) -> ())?) -> URLSessionTask? {
        var params: ParamsDictionary = [
            "fileURL": activityFileURL,
            "fileName": activityFileURL.lastPathComponent
        ]
        if let type = type {
            params["activity_type"] = type
        }
        if let name = name {
            params["name"] = name
        }
        if let description = description {
            params["description"] = description
        }
        let fileURL = activityFileURL as NSURL
        let fileType = fileURL.pathExtension
        params["data_type"] = fileType

        return request(.POST, authenticated: true, path: UploadResourcePath.Upload.rawValue, params: params, completionHandler: { (response, error) in
            if let error = error {
                DispatchQueue.main.async {
                    completionHandler?(false, error)
                }
                return
            }

            handleUploadResponse(response, completionHandler: completionHandler)
        })
    }

    internal static func handleUploadResponse(_ response: Any?, completionHandler:((_ status: Bool, _ error: NSError?) -> ())?) {
        if let details = response as? JSONDictionary {
            NSLog("Upload status: \(String(describing: details["status"]))")

            var success: Bool = true
            if let _ = details["error"] as? String {
                success = false
            }

            DispatchQueue.main.async {
                if !success {
                    let error = Strava.error(.undefinedError, reason: String(describing: details["error"]))
                    completionHandler?(success, error)
                }
                else {
                    completionHandler?(success, nil)
                }
            }
        }
        else {
            DispatchQueue.main.async {
                let error = Strava.error(.invalidResponse, reason: "Invalid Response")
                completionHandler?(false, error)
            }
        }
    }
}
