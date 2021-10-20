def grade_assignment(possible_submission_folders, submission_name)
    # (ideally `possible_submission_folders` would only have one iteam but sometimes there are false positives)
    results = []
    for each_folder in possible_submission_folders
        # skip the __pycache__ and __MACOSX folders
        if each_folder =~ /\/(__pycache__|__MACOSX)\//
            next
        end
        
        # get the student's name & UIN
        name_and_uin = submission_name.sub(/(\w+)_(\d+)_(\d\d\d\d\d\d\d\d).+/,"\\1,\\3")
        name, uin = name_and_uin.split(",")
        
        # 
        # run the command
        # 
        command_result = nil
        FileSystem.in_dir(each_folder) do
            command_result = Console.run!(["python", each_folder/"autograder.py"])
        end
        
        # 
        # extract score
        # 
        output = command_result.text
        total = output.gsub(/[\w\W]*(Total: .+)[\w\W]*\z/, "\\1")
        if total and total =~ /Total/
            total = total.gsub(/Total: /,"")
        else
            total = nil
        end
        
        # 
        # save data
        # 
        results.push({
            "name" => name,
            "uin" => uin,
            "grade" => total,
            "folder" => each_folder,
            "autograder_output" => output.gsub(/\t/,"    "),
        })
    end
    return results
end