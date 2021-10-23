require_relative "./minified_toolbox.rb"
require_relative "./generate_working_spaces.rb"

# 
# arguments
# 
@which_project = Console.args[0]
if not @which_project
    puts "You forgot to tell me what project to grade"
    exit(1)
end

@which_submission = Console.args[1]

# 
# main vars/paths
# 
@grading_folder = Dir.pwd/"projects"/@which_project
@submissions_zip              = @grading_folder/"submissions.zip"
@workspace_folder             = @grading_folder/"workspace"
@output_file                  = @grading_folder/"results.yml"
@project_template_folder      = @grading_folder/"template_code"
@folder_for_unzipped_projects = @workspace_folder/"submissions/"
@folder_for_zipped_submissions = @workspace_folder/"zipped_submissions/"
require_relative( Dir.pwd/"projects"/@which_project/"grader.rb" )
# we get the below variables from here^
#     @main_file                             
#     @folder_relative_to_main_file          
#     @overwrite_submission_files_for_grading



# 
# for running
# 
run_one_submission = ->(each_zip, index) do
    submission_name = FS.basename(each_zip)
    puts "grading #{index}/#{submission_zips.size}: #{submission_name}"
    submission_folder = output_location/submission_name
    success = Console.run?(["unzip", each_zip, "-d", submission_folder ])
    if not success
        grades[submission_name] = "failed to unzip"
    else
        # 
        # combine their code with template code
        # 
        folders = generate_working_spaces(
            working_spaces_folder: @workspace_folder,
            submission_folder: submission_folder,
            id_path: @main_file,
            path_relative_to_id: @folder_relative_to_main_file,
            files_to_overwrite: @overwrite_submission_files_for_grading,
            template_folder: @project_template_folder,
        )
        if folders.empty?
            grades[submission_name] = "failed to generate any workspaces, because couldn't find parent folder for: #{@main_file}"
        end
        begin
            grades[submission_name] = grade_assignment(folders, submission_name)
        rescue => exception
            grades[submission_name] = "there was an error when running the grader: #{exception}"
        end
    end
    # save result after every run
    FS.write(grades.to_yaml, to: @output_file)    
end

# 
# 
# grade one
# 
# 
if @which_submission.is_a? String
    submission_path = @folder_for_zipped_submissions/@which_submission
    unzipped_submission_path = @folder_for_unzipped_projects/@which_submission
    
    # 
    # make sure it exists
    # 
    if not FS.file?(submission_path)
        raise <<~HEREDOC
            
            
            I looked for #{@which_submission}
            But I didn't see a zip file at #{submission_path}
        HEREDOC
    end
    
    # 
    # unzip
    # 
    FS.ensure_folder_exists(@folder_for_unzipped_projects)
    success = Console.run?(["unzip", submission_path, "-d", unzipped_submission_path ])
    if not success
        raise <<~HEREDOC
            
            
            Tried to run `unzip` on #{submission_path} to #{unzipped_submission_path} but it failed
        HEREDOC
    end
    
    #
    # grade one
    # 
    run_one_submission[ unzipped_submission_path, 0 ]

# 
# 
# grade all
# 
# 
else
    # 
    # ask about clearing out workspace
    # 
    if FS.exists?(@workspace_folder)
        puts "Looks like a workspace folder already exists"
        print "Would you like me to clear it out? "
        answer = ""
        loop do
            answer = STDIN.gets
            if answer =~ /[yY]/
                puts "Okay"
                FS.delete(@workspace_folder)
                FS.touch_dir(@workspace_folder)
                break
            elsif answer =~ /[nN]/
                puts "Okay"
                break
            else
                puts "(please answer with yes or no)"
            end
        end
    end

    # 
    # unzip main
    # 
    puts "starting to unzip main"
    FS.ensure_folder_exists(@workspace_folder)
    success = Console.run?(["unzip", @submissions_zip, "-d", @folder_for_zipped_submissions ])
    if not success
        raise <<~HEREDOC
            
            
            Tried to run `unzip` on #{@submissions_zip} to #{@folder_for_zipped_submissions} but it failed
        HEREDOC
    else
        puts "finished unzipping main"
    end

    # 
    # unzip + run each
    # 
    grades = YAML.load_file(@output_file) rescue {}
    grades = {} if not grades.is_a?(Hash)
    FS.ensure_folder_exists(@folder_for_unzipped_projects)
    submission_zips = FS.glob(@folder_for_zipped_submissions/"*.zip")
    index = 0
    for each_zip in submission_zips
        index += 1
        run_one_submission[each_zip, index]
    end
end