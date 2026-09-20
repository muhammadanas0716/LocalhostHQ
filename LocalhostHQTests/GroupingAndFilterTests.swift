import Testing
@testable import LocalhostHQ

@Suite("Service grouping")
struct ServiceGrouperTests {
    private let grouper = ServiceGrouper()

    @Test("Services sharing a repository group under its folder name")
    func groupsByRepository() {
        let groups = grouper.group([SampleData.api, SampleData.web])
        let dicee = groups.first { $0.title == "dicee" }

        #expect(dicee != nil)
        #expect(dicee?.services.count == 2)
        #expect(dicee?.kind == .repository)
        // Sorted by port, so :3000 precedes :8787 regardless of input order.
        #expect(dicee?.services.map(\.port) == [3000, 8787])
    }

    @Test("Infrastructure lands in its own section, not a fake project")
    func infrastructureIsSeparate() {
        let groups = grouper.group([SampleData.postgres, SampleData.redis])

        #expect(groups.count == 1)
        #expect(groups[0].kind == .infrastructure)
        #expect(groups[0].title == "Infrastructure")
        #expect(groups[0].directory == nil)
    }

    @Test("Section order is repositories, then dev servers, then infrastructure")
    func sectionOrder() {
        let groups = grouper.group([SampleData.postgres, SampleData.jupyter, SampleData.web])
        #expect(groups.map(\.kind) == [.repository, .development, .infrastructure])
    }

    @Test("Ordering is stable regardless of discovery order")
    func stableOrdering() {
        let forward = grouper.group(SampleData.all)
        let reversed = grouper.group(SampleData.all.reversed())

        #expect(forward.map(\.id) == reversed.map(\.id))
        #expect(forward.map { $0.services.map(\.id) } == reversed.map { $0.services.map(\.id) })
    }

    @Test("Repositories sort alphabetically")
    func repositoriesSortAlphabetically() {
        let groups = grouper.group([SampleData.vite, SampleData.web])
        let repositories = groups.filter { $0.kind == .repository }
        #expect(repositories.map(\.title) == ["dicee", "portfolio"])
    }

    @Test("Empty input produces no sections")
    func emptyInput() {
        #expect(grouper.group([]).isEmpty)
    }

    @Test("System services are separated from the developer's own")
    func systemServicesSeparated() {
        var system = SampleData.redis
        system = LocalService(
            id: system.id, listeningPort: system.listeningPort, process: system.process,
            project: system.project, detection: system.detection, git: system.git,
            metrics: system.metrics, origin: .system
        )

        let groups = grouper.group([SampleData.web, system])
        #expect(groups.map(\.kind) == [.repository, .system])
    }
}

@Suite("Search filtering")
struct ServiceFilterTests {
    private let filter = ServiceFilter()

    @Test("An empty query matches everything")
    func emptyQuery() {
        #expect(filter.apply(query: "", to: SampleData.all).count == SampleData.all.count)
        #expect(filter.apply(query: "   ", to: SampleData.all).count == SampleData.all.count)
    }

    @Test("Matches by port")
    func byPort() {
        let results = filter.apply(query: "3000", to: SampleData.all)
        #expect(results.map(\.port) == [3000])
    }

    @Test("Matches by framework, case-insensitively")
    func byFramework() {
        #expect(filter.apply(query: "next", to: SampleData.all).first?.port == 3000)
        #expect(filter.apply(query: "NEXT.JS", to: SampleData.all).first?.port == 3000)
    }

    @Test("Matches by repository path")
    func byPath() {
        let results = filter.apply(query: "dicee", to: SampleData.all)
        #expect(results.count == 2)
        #expect(Set(results.map(\.port)) == [3000, 8787])
    }

    @Test("Matches by git branch")
    func byBranch() {
        let results = filter.apply(query: "redesign", to: SampleData.all)
        #expect(results.map(\.port) == [5173])
    }

    @Test("Multiple terms narrow rather than widen")
    func multipleTermsNarrow() {
        let broad = filter.apply(query: "dicee", to: SampleData.all)
        let narrow = filter.apply(query: "dicee 8787", to: SampleData.all)

        #expect(broad.count == 2)
        #expect(narrow.count == 1)
        #expect(narrow.first?.port == 8787)
    }

    @Test("A query matching nothing returns nothing")
    func noMatches() {
        #expect(filter.apply(query: "kubernetes", to: SampleData.all).isEmpty)
    }

    @Test("Matches by PID")
    func byPID() {
        #expect(filter.apply(query: "4812", to: SampleData.all).first?.port == 3000)
    }
}
