require_relative "./minified_toolbox.rb"
require_relative "./generate_working_spaces.rb"

# 
# arguments
# 
which_project = Console.args[0]
if not which_project
    puts "You forgot to tell me what project to grade"
    exit(1)
end


# 
# main vars/paths
# 
grading_folder = Dir.pwd/"projects"/which_project
@setup_file              = grading_folder/"setup.yml"
@submissions_zip         = grading_folder/"submissions.zip"
@workspace_folder        = grading_folder/"workspace"
@output_file             = grading_folder/"results.yml"
@project_template_folder = grading_folder/"template_code"
setup = YAML.load_file(@setup_file)
@main_file                    = setup["main_file"]
@folder_relative_to_main_file = setup["folder_relative_to_main_file"]
@overwrite_submission_files_for_grading = setup["overwrite_submission_files_for_grading"]
require_relative( Dir.pwd/"projects"/which_project/"grader.rb" )


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
intermediate_location = @workspace_folder/"zipped_submissions.ignore/"
FS.ensure_folder_exists(@workspace_folder)
success = Console.run?(["unzip", @submissions_zip, "-d", intermediate_location ])
if not success
    raise <<~HEREDOC
        
        
        Tried to run `unzip` on #{@submissions_zip} to #{intermediate_location} but it failed
    HEREDOC
else
    puts "finished unzipping main"
end

# 
# unzip + run each
# 
grades = {}
begin
    grades = YAML.load_file(@output_file)
rescue => exception
end
if not grades.is_a?(Hash)
    grades = {}
end
output_location = @workspace_folder/"submissions.ignore/"
FS.ensure_folder_exists(output_location)
submission_zips = FS.glob(intermediate_location/"*.zip")
index = 0
for each_zip in submission_zips
    index += 1
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




