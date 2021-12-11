require_relative "./minified_toolbox.rb"

def generate_working_spaces(working_spaces_folder:nil, submission_folder:nil, id_path:nil, path_relative_to_id:nil, files_to_overwrite:nil, template_folder:nil)
    working_spaces = []
    if not FS.is_folder(submission_folder)
        puts "Tried generating workspaces using files in #{submission_folder}, but #{submission_folder} is not a folder"
        return working_spaces
    end
    
    FS.ensure_folder_exists(working_spaces_folder)
    biggest_workspace_number =  ([0].concat(Dir.children(working_spaces_folder).map(&:to_i))).max
    
    # 
    # find a particular path
    # 
    id_items = id_path.split(/\//).reverse
    valid_paths = []
    for each in FS.glob(submission_folder/"**/*")
        items = each.split(/\//).reverse
        item_matches_id = id_items.zip(items).map{|each| each[0] == each[1] }.all?
        if item_matches_id
            valid_paths.push(each)
        end
    end
    valid_starting_points = valid_paths.map{|each| File.realpath(each/path_relative_to_id) }
    if valid_starting_points.size == 0
        return working_spaces
    end
    for each_valid_starting_point in valid_starting_points
        biggest_workspace_number += 1
        workspace_path = working_spaces_folder/"#{biggest_workspace_number}"
        FS.ensure_folder_exists(workspace_path)
        begin
            # 
            # copy all submission files into working space
            # 
            for each_item in Dir.children(each_valid_starting_point)
                FS.copy(each_item, from: each_valid_starting_point, to: workspace_path)
            end
            
            # 
            # copy any missing files
            # 
            for each_item in Dir.children(template_folder)
                # if not in the workspace
                if not FS.exists?(workspace_path/each_item)
                    FS.copy(each_item, from: template_folder, to: workspace_path)
                end
            end
            
            # 
            # overwrite certain files
            # 
            for each_item in files_to_overwrite
                # delete anything in the way
                FS.delete(workspace_path/each_item)
                # copy the file to the template (syslinks can mess with stuff, like screwing up the python path/relative imports)
                FS.copy(each_item, from: template_folder, to: workspace_path)
            end
            working_spaces.push(workspace_path)
        rescue => exception
            puts exception
            puts exception.backtrace
        end
    end
    return working_spaces
end