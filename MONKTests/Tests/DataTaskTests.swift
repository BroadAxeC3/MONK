//
//  DataTaskTests.swift
//  MONK
//
//  MIT License
//
//  Copyright (c) 2017 Mobelux
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import XCTest
@testable import MONK

class DataTaskTests: XCTestCase {
    
    private let networkController = NetworkController(serverTrustSettings: nil)
    private let sessionController = URLSession.shared
    
    override func tearDown() {
        super.tearDown()
        networkController.cancelAllTasks()
    }
    
    func testSystemDataTask() {
        let expectation = self.expectation(description: "Network request")
        
        let url = URL(string: "http://jsonplaceholder.typicode.com/posts/1")!

        let task = sessionController.dataTask(with: url) { (data, response, error) in
            XCTAssertNil(error, "Error found")
            if let httpResponse = response as? HTTPURLResponse {
                XCTAssert(httpResponse.statusCode == 200, "Invalid status code found")
            }
            XCTAssertNotNil(data, "Data was nil")
            let expectedData = DataHelper.data(for: .posts1)
            let expectedJSON = try! expectedData.json()
            let recievedJSON = try? data!.json()
            
            XCTAssert(recievedJSON != nil && recievedJSON! == expectedJSON, "Unexpected data found")
            expectation.fulfill()
        }
        task.resume()
        waitForExpectations(timeout: TestConstants.testTimeout, handler: nil)
    }
    
    func testBasicDataTask() {
        let expectation = self.expectation(description: "Network request")
        
        let url = URL(string: "http://jsonplaceholder.typicode.com/posts/1")!
        let request = DataRequest(url: url, httpMethod: .get)
        let task = networkController.data(with: request)
        
        task.addCompletion { (result) in
            switch result {
            case .failure(let error):
                XCTAssert(false, "Error found: \(String(describing: error))")
                expectation.fulfill()
            case .success(let statusCode, let responseData, let cached):
                XCTAssert(statusCode == 200, "Invalid status code found")
                XCTAssertNotNil(responseData, "Data was nil")
                switch cached {
                case .notCached:
                    break
                case .fromCache, .updatedCache:
                    XCTAssert(false, "We should not have used the cache")
                }
                let expectedData = DataHelper.data(for: .posts1)
                let expectedJSON = try! expectedData.json()
                let recievedJSON = try? responseData!.json()
                
                XCTAssert(recievedJSON != nil && recievedJSON! == expectedJSON, "Unexpected data found")
                XCTAssert(self.networkController.activeTasksCount == 0, "Tasks still active")
                
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1, execute: {
                    let mutableTask = task as! MutableDataTask
                    XCTAssert(mutableTask.completionHandlers.count == 0, "Completion handlers aren't dealocated")
                    XCTAssert(mutableTask.progressHandlers.count == 0, "Progress handlers aren't dealocated")
                    expectation.fulfill()
                })
            }
        }
        
        task.resume()
        waitForExpectations(timeout: TestConstants.testTimeout, handler: nil)
    }
    
    func testDataTaskProgress() {
        let expectation = self.expectation(description: "Large network request")
        
        let url = URL(string: "http://jsonplaceholder.typicode.com/photos")!
        let request = DataRequest(url: url, httpMethod: .get)
        let task = networkController.data(with: request)
        
        var progressCalled = false
        
        task.addCompletion { (result) in
            switch result {
            case .failure(let error):
                XCTAssert(false, "Error found: \(String(describing: error))")
                expectation.fulfill()
            case .success(let statusCode, let responseData, let cached):
                XCTAssert(statusCode == 200, "Invalid status code found")
                XCTAssertNotNil(responseData, "Data was nil")
                switch cached {
                case .notCached:
                    break
                case .fromCache, .updatedCache:
                    XCTAssert(false, "We should not have used the cache")
                }
                XCTAssert(progressCalled, "Progress was never called")
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1, execute: {
                    let mutableTask = task as! MutableDataTask
                    XCTAssert(mutableTask.completionHandlers.count == 0, "Completion handlers aren't dealocated")
                    XCTAssert(mutableTask.progressHandlers.count == 0, "Progress handlers aren't dealocated")
                    expectation.fulfill()
                })
            }
        }
        
        task.addProgress { (progress) in
            XCTAssertNotNil(task.downloadProgress, "Download progress wasn't set")
            XCTAssert(progress.totalBytes == task.downloadProgress!.totalBytes, "Total bytes don't match")
            XCTAssert(progress.completeBytes == task.downloadProgress!.completeBytes, "Complete bytes don't match")
            XCTAssert(progress.progress == task.downloadProgress!.progress, "Progresses don't match")
            XCTAssertNil(progress.progress, "Progress wasn't nil, but we expected it to be nil")
            XCTAssert(progress.totalBytes == -1, "This API doesn't return the total bytes for a data request")
            progressCalled = true
        }
        
        task.resume()
        waitForExpectations(timeout: TestConstants.testTimeout, handler: nil)
    }
    
    func testAutomaticRedirection() {
        let expectation = self.expectation(description: "Redirection network request")
        let finalURLString = "https://jsonplaceholder.typicode.com/posts/1".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        
        let url = URL(string: "https://httpbin.org/redirect-to?url=\(finalURLString!)")!
        let request = DataRequest(url: url, httpMethod: .get)
        let task = networkController.data(with: request)
        
        var progressCalled = false
        
        task.addCompletion { (result) in
            switch result {
            case .failure(let error):
                XCTAssert(false, "Error found: \(String(describing: error))")
                expectation.fulfill()
            case .success(let statusCode, let responseData, let cached):
                XCTAssert(statusCode == 200, "Invalid status code found")
                XCTAssertNotNil(responseData, "Data was nil")
                switch cached {
                case .notCached:
                    break
                case .fromCache, .updatedCache:
                    XCTAssert(false, "We should not have used the cache")
                }
                let expectedData = DataHelper.data(for: .posts1)
                let expectedJSON = try! expectedData.json()
                let recievedJSON = try? responseData!.json()
                
                XCTAssert(recievedJSON != nil && recievedJSON! == expectedJSON, "Unexpected data found")
                
                XCTAssert(progressCalled, "Progress was never called")
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1, execute: {
                    let mutableTask = task as! MutableDataTask
                    XCTAssert(mutableTask.completionHandlers.count == 0, "Completion handlers aren't dealocated")
                    XCTAssert(mutableTask.progressHandlers.count == 0, "Progress handlers aren't dealocated")
                    expectation.fulfill()
                })
            }
        }
        
        task.addProgress { (progress) in
            XCTAssertNotNil(task.downloadProgress, "Download progress wasn't set")
            XCTAssert(progress.totalBytes == task.downloadProgress!.totalBytes, "Total bytes don't match")
            XCTAssert(progress.completeBytes == task.downloadProgress!.completeBytes, "Complete bytes don't match")
            XCTAssert(progress.progress == task.downloadProgress!.progress, "Progresses don't match")
            progressCalled = true
        }
        
        task.resume()
        waitForExpectations(timeout: TestConstants.testTimeout, handler: nil)
    }
    
    func testPostWithoutBody() {
        let expectation = self.expectation(description: "Network request")
        
        let url = URL(string: "http://httpbin.org/post")!
        
        let request = DataRequest(url: url, httpMethod: .post(bodyData: nil))
        let task = networkController.data(with: request)
        
        var downloadProgressCalled = false
        var uploadProgressCalled = false
        
        task.addCompletion { (result) in
            switch result {
            case .failure(let error):
                XCTAssert(false, "Error found: \(String(describing: error))")
                expectation.fulfill()
            case .success(let statusCode, let responseData, let cached):
                XCTAssert(statusCode == 200, "Invalid status code found")
                XCTAssertNotNil(responseData, "Data was nil")
                switch cached {
                case .notCached:
                    break
                case .fromCache, .updatedCache:
                    XCTAssert(false, "We should not have used the cache")
                }
                
                XCTAssert(self.networkController.activeTasksCount == 0, "Tasks still active")

                XCTAssert(downloadProgressCalled, "Download progress was never called")
                XCTAssertFalse(uploadProgressCalled, "Upload progress was called")
                
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1, execute: {
                    let mutableTask = task as! MutableDataTask
                    XCTAssert(mutableTask.completionHandlers.count == 0, "Completion handlers aren't dealocated")
                    XCTAssert(mutableTask.progressHandlers.count == 0, "Progress handlers aren't dealocated")
                    XCTAssert(mutableTask.uploadProgressHandlers.count == 0, "Progress handlers aren't dealocated")
                    expectation.fulfill()
                })
            }
        }
        
        task.addProgress { (progress) in
            XCTAssertNotNil(task.downloadProgress, "Download progress wasn't set")
            XCTAssert(progress.totalBytes == task.downloadProgress!.totalBytes, "Total bytes don't match")
            XCTAssert(progress.completeBytes == task.downloadProgress!.completeBytes, "Complete bytes don't match")
            XCTAssert(progress.progress == task.downloadProgress!.progress, "Progresses don't match")
            XCTAssertNotNil(progress.progress, "Progress was nil")
            XCTAssert(progress.totalBytes >= progress.completeBytes, "Total bytes should always be more then complete bytes")
            downloadProgressCalled = true
        }
        
        task.addUploadProgress { (progress) in
            XCTAssertNotNil(task.uploadProgress, "Upload progress wasn't set")
            XCTAssert(progress.totalBytes == task.uploadProgress!.totalBytes, "Total bytes don't match")
            XCTAssert(progress.completeBytes == task.uploadProgress!.completeBytes, "Complete bytes don't match")
            XCTAssert(progress.progress == task.uploadProgress!.progress, "Progresses don't match")
            XCTAssertNotNil(progress.progress, "Progress was nil")
            XCTAssert(progress.totalBytes >= progress.completeBytes, "Total bytes should always be more then complete bytes")
            uploadProgressCalled = true
        }
        
        task.resume()
        waitForExpectations(timeout: TestConstants.testTimeout, handler: nil)
    }

    func testPutWithoutBody() {
        let expectation = self.expectation(description: "Network request")
        
        let url = URL(string: "http://httpbin.org/put")!
        
        let request = DataRequest(url: url, httpMethod: .put(bodyData: nil))
        let task = networkController.data(with: request)
        
        var downloadProgressCalled = false
        var uploadProgressCalled = false
        
        task.addCompletion { (result) in
            switch result {
            case .failure(let error):
                XCTAssert(false, "Error found: \(String(describing: error))")
                expectation.fulfill()
            case .success(let statusCode, let responseData, let cached):
                XCTAssert(statusCode == 200, "Invalid status code found")
                XCTAssertNotNil(responseData, "Data was nil")
                switch cached {
                case .notCached:
                    break
                case .fromCache, .updatedCache:
                    XCTAssert(false, "We should not have used the cache")
                }
                
                XCTAssert(self.networkController.activeTasksCount == 0, "Tasks still active")
                
                XCTAssert(downloadProgressCalled, "Download progress was never called")
                XCTAssertFalse(uploadProgressCalled, "Upload progress was called")
                
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1, execute: { 
                    let mutableTask = task as! MutableDataTask
                    XCTAssert(mutableTask.completionHandlers.count == 0, "Completion handlers aren't dealocated")
                    XCTAssert(mutableTask.progressHandlers.count == 0, "Progress handlers aren't dealocated")
                    XCTAssert(mutableTask.uploadProgressHandlers.count == 0, "Progress handlers aren't dealocated")
                    expectation.fulfill()
                })
            }
        }
        
        task.addProgress { (progress) in
            XCTAssertNotNil(task.downloadProgress, "Download progress wasn't set")
            XCTAssert(progress.totalBytes == task.downloadProgress!.totalBytes, "Total bytes don't match")
            XCTAssert(progress.completeBytes == task.downloadProgress!.completeBytes, "Complete bytes don't match")
            XCTAssert(progress.progress == task.downloadProgress!.progress, "Progresses don't match")
            XCTAssertNotNil(progress.progress, "Progress was nil")
            XCTAssert(progress.totalBytes >= progress.completeBytes, "Total bytes should always be more then complete bytes")
            downloadProgressCalled = true
        }
        
        task.addUploadProgress { (progress) in
            XCTAssertNotNil(task.uploadProgress, "Upload progress wasn't set")
            XCTAssert(progress.totalBytes == task.uploadProgress!.totalBytes, "Total bytes don't match")
            XCTAssert(progress.completeBytes == task.uploadProgress!.completeBytes, "Complete bytes don't match")
            XCTAssert(progress.progress == task.uploadProgress!.progress, "Progresses don't match")
            XCTAssertNotNil(progress.progress, "Progress was nil")
            XCTAssert(progress.totalBytes >= progress.completeBytes, "Total bytes should always be more then complete bytes")
            uploadProgressCalled = true
        }
        
        task.resume()
        waitForExpectations(timeout: TestConstants.testTimeout, handler: nil)
    }
}
