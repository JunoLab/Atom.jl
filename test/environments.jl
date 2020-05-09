@testset "environment" begin
    using Pkg

    try
        Pkg.activate(atomjldir)

        # test status check
        @test !isempty(Atom.project_status())

        @static VERSION ≥ v"1.4" && begin

        # test current project info
        prj_info = Atom.project_info()
        @test prj_info.name == "Atom"
        @test prj_info.path == joinpath(atomjldir, "Project.toml")

        # test all active project listing: at least environment for this package is active
        prjs = Atom.allprojects()
        @test Atom.project_info() in prjs.projects
        @test prjs.active == "Atom"

        end  # if VERSION ≥ v"1.4"
    finally
        Pkg.activate()
    end
end
