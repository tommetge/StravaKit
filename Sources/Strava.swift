//
//  Strava.swift
//  StravaKit
//
//  Created by Brennan Stehling on 8/18/16.
//  Copyright © 2016 SmallSharpTools LLC. All rights reserved.
//
// Implementation influenced by LyftKit created by Genady Okrain.
//
// Strava API
// See: http://strava.github.io/api/

import Foundation
import Security

/** JSON Dictionary */
public typealias JSONDictionary = [String : Any]
/** JSON Array */
public typealias JSONArray = [JSONDictionary]
/** Params Dictionary */
public typealias ParamsDictionary = [String : Any]

/** Strava Base URL */
public let StravaBaseURL = "https://www.strava.com"
/** Strava Error Domain */
public let StravaErrorDomain = "StravaKit"

/** Rate Limit HTTP Header Key for Limit */
public let RateLimitLimitHeaderKey = "X-Ratelimit-Limit"
/** Rate Limit HTTP Header Key for Usage */
public let RateLimitUsageHeaderKey = "X-Ratelimit-Usage"

/** Rate Limit Notification Key for Limit */
public let RateLimitLimitKey = "Rate-Limit-Limit"
/** Rate Limit Notification Key for Usage */
public let RateLimitUsageKey = "Rate-Limit-Usage"

/**
 HTTP Methods

 - GET: Get method.
 - POST: Post method.
 - PUT: Put method.
 */
@objc public enum HTTPMethod: Int {
    case GET
    case POST
    case PUT

    public typealias RawValue = String

    public var rawValue: RawValue {
        switch self {
        case .GET:
            return "GET"
        case .POST:
            return "POST"
        case .PUT:
            return "PUT"
        }
    }

    public init?(rawValue: RawValue) {
        switch rawValue {
        case "GET":
            self = .GET
        case "POST":
            self = .POST
        case "PUT":
            self = .PUT
        default:
            self = .GET
        }
    }
}

/** Strava Error Codes */
@objc public enum StravaErrorCode: Int {
    /** Error on backend. */
    case remoteError = 501
    /** Required credentials were missing. */
    case missingCredentials = 502
    /** Access Token was not found. */
    case noAccessToken = 503
    /** Response was not returned. */
    case noResponse = 504
    /** Response was not expected. */
    case invalidResponse = 505
    /** Requested resource was not found. */
    case recordNotFound = 506
    /** Request exceeded rate limit. See error for details. */
    case rateLimitExceeded = 507
    /** Access is not allowed. */
    case accessForbidden = 508
    /** Request is not supported. */
    case unsupportedRequest = 509
    /** Reason for error is not known. */
    case undefinedError = 599
}

/**
 Strava class for handling all API endpoint requests.
 */
@objc open class Strava: NSObject {

    internal static let sharedInstance = Strava()
    internal let dateFormatter = DateFormatter()
    internal var clientId: String?
    internal var clientSecret: String?
    internal var redirectURI: String?
    internal var accessToken: String?
    internal var athlete: Athlete?
    internal var defaultRequestor: Requestor = DefaultRequestor()
    internal var alternateRequestor: Requestor?
    internal var isDebugging: Bool = false

    /**
     Strava initializer which should not be accessed externally.
     */
    override internal init() {
        super.init()

        loadAccessData()

        // Use ISO 8601 standard format for date strings
        // Docs: http://strava.github.io/api/#dates
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZ"
    }

    /**
     Indicates if the current athlete is defined with a profile and access token.
     */
    open static var isAuthorized: Bool {
        return sharedInstance.accessToken != nil && sharedInstance.athlete != nil
    }

    /**
     Current Athlete which is authorized.
     */
    open static var currentAthlete: Athlete? {
        return sharedInstance.athlete
    }

    /**
     Allows for enabling debugging. It is false by default.
     */
    open static var isDebugging: Bool {
        get {
            return sharedInstance.isDebugging
        }
        set {
            sharedInstance.isDebugging = newValue
        }
    }

    open static func replaceId(id: Int, in path: String) -> String {
        return path.replacingOccurrences(of: ":id", with: String(id))
    }

    open static func configure(accessToken: String?, athleteDictionary: JSONDictionary? = nil, alternateRequestor: Requestor? = nil) {
        sharedInstance.accessToken = accessToken
        sharedInstance.athlete = Athlete(dictionary: athleteDictionary ?? [:])
        sharedInstance.alternateRequestor = alternateRequestor
    }

    /**
     Request method for all StravaKit API endpoint calls.
     */
    @discardableResult
    open static func request(_ method: HTTPMethod, authenticated: Bool, path: String, params: [String: Any]?, completionHandler: ((_ response: Any?, _ error: NSError?) -> ())?) -> URLSessionTask? {
        if isDebugging {
            debugPrint("Method: \(method.rawValue), Path: \(path), Authenticated: \(authenticated)")
            if let params = params {
                debugPrint("Params: \(params)")
            }
        }
        if let alternateRequestor = sharedInstance.alternateRequestor {
            return alternateRequestor.request(method, authenticated: authenticated, path: path, params: params, completionHandler: completionHandler)
        }

        return sharedInstance.defaultRequestor.request(method, authenticated: authenticated, path: path, params: params, completionHandler: completionHandler)
    }

    // MARK: - Internal Functions -

    internal static func error(_ code: StravaErrorCode, reason: String, userInfo: [String : Any]? = [:]) -> NSError {
        var dictionary: [String : Any]? = userInfo
        dictionary?[NSLocalizedDescriptionKey] = reason as Any?

        let error = NSError(domain: StravaErrorDomain, code: code.rawValue, userInfo: dictionary)
        return error
    }

    internal static func urlWithString(_ string: String?, parameters: JSONDictionary?) -> URL? {
        guard let string = string
            else {
            return nil
        }

        let aURL = URL(string: string)
        if aURL?.scheme != "http" && aURL?.scheme != "https" {
            return nil
        }

        if let parameters = parameters {
            return appendQueryParameters(parameters, aURL: aURL)
        }

        return aURL
    }

    internal static func appendQueryParameters(_ parameters: JSONDictionary, aURL: URL?) -> URL? {
        guard let aURL = aURL,
            var components = URLComponents(url: aURL, resolvingAgainstBaseURL: false)
            else {
                return nil
        }

        var queryItems: [URLQueryItem] = []

        for key in parameters.keys {
            let value = parameters[key]
            if let stringValue = value as? String {
                let queryItem: URLQueryItem = URLQueryItem(name: key, value: stringValue)
                queryItems.append(queryItem)
            }
            else if let value = value {
                let stringValue = "\(value)"
                let queryItem: URLQueryItem = URLQueryItem(name: key, value: stringValue)
                queryItems.append(queryItem)
            }
        }

        components.queryItems = queryItems

        return components.url
    }

    internal static func dateFromString(_ string: String?) -> Date? {
        if let string = string {
            return sharedInstance.dateFormatter.date(from: string)
        }
        return nil
    }

}
